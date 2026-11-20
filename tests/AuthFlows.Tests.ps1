# End-to-end auth-flow tests through the public module surface (Connect-Hive,
# Complete-HiveLogin, Get-HiveAuthState, Disconnect-Hive). All Cognito traffic
# is replayed by a Pester mock installed inside the PoSHive module scope.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PoSHive.psd1') -Force
    $script:M = Get-Module PoSHive
    $script:Kat = Get-Content (Join-Path $PSScriptRoot 'SrpKnownAnswers.json') -Raw | ConvertFrom-Json
    $script:PoolId = $script:Kat.inputs.pool_id
    $script:Caches = @()
    # Shared mutable scenario flag the mock closure reads.
    $script:State = @{ Scenario = 'none' }
}

AfterAll {
    $script:Caches | Remove-Item -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-Hive / Complete-HiveLogin auth flows' {
    BeforeAll {
        $Kat = $script:Kat
        $State = $script:State
        $body = {
            param($Uri, $Headers, $Body)
            function MockResponse([int]$Status, $Body) {
                return [pscustomobject]@{ StatusCode = $Status; Content = (ConvertTo-Json $Body -Depth 12 -Compress) }
            }
            $Scenario = $State.Scenario
            $target = ($Headers['X-Amz-Target'] -replace '^AWSCognitoIdentityProviderService\.', '')
            $req = if ($Body) { $Body | ConvertFrom-Json } else { $null }
            $pvParams = @{ USER_ID_FOR_SRP = 'me@example.com'; SALT = $Kat.inputs.salt_hex; SRP_B = $Kat.inputs.srp_b_hex; SECRET_BLOCK = $Kat.inputs.secret_block_b64 }
            $devParams = @{ SALT = $Kat.inputs.device_salt_hex; SRP_B = $Kat.inputs.srp_b_hex; SECRET_BLOCK = $Kat.inputs.secret_block_b64 }

            switch ("$Scenario/$target") {
                'fresh-login/InitiateAuth' {
                    if ($req.AuthFlow -ne 'USER_SRP_AUTH' -or -not $req.AuthParameters.SRP_A) { return MockResponse 400 @{ __type='x#InvalidParameterException'; message='expected SRP_A' } }
                    return MockResponse 200 @{ ChallengeName='PASSWORD_VERIFIER'; ChallengeParameters=$pvParams; Session='sess-1' }
                }
                'fresh-login/RespondToAuthChallenge' {
                    if ($req.ChallengeName -ne 'PASSWORD_VERIFIER') { return MockResponse 400 @{ __type='x#InvalidParameterException'; message="unexpected $($req.ChallengeName)" } }
                    if (-not $req.ChallengeResponses.PASSWORD_CLAIM_SIGNATURE -or -not $req.ChallengeResponses.PASSWORD_CLAIM_SECRET_BLOCK -or -not $req.ChallengeResponses.TIMESTAMP) {
                        return MockResponse 400 @{ __type='x#NotAuthorizedException'; message='missing claim fields' }
                    }
                    return MockResponse 200 @{ ChallengeName='SMS_MFA'; Session='sess-mfa'; ChallengeParameters=@{ CODE_DELIVERY_DESTINATION='+447*******45' } }
                }
                'e2e/InitiateAuth' {
                    if ($req.AuthFlow -ne 'USER_SRP_AUTH' -or -not $req.AuthParameters.SRP_A) { return MockResponse 400 @{ __type='x#InvalidParameterException'; message='expected SRP_A' } }
                    return MockResponse 200 @{ ChallengeName='PASSWORD_VERIFIER'; ChallengeParameters=$pvParams; Session='sess-1' }
                }
                'e2e/RespondToAuthChallenge' {
                    switch ($req.ChallengeName) {
                        'PASSWORD_VERIFIER' {
                            if (-not $req.ChallengeResponses.PASSWORD_CLAIM_SIGNATURE) { return MockResponse 400 @{ __type='x#NotAuthorizedException'; message='missing claim fields' } }
                            return MockResponse 200 @{ ChallengeName='SMS_MFA'; Session='sess-mfa'; ChallengeParameters=@{ CODE_DELIVERY_DESTINATION='+447*******45' } }
                        }
                        'SMS_MFA' {
                            if ($req.ChallengeResponses.SMS_MFA_CODE -ne '123456') { return MockResponse 400 @{ __type='x#CodeMismatchException'; message='Invalid verification code provided, please try again.' } }
                            return MockResponse 200 @{ AuthenticationResult=@{ IdToken='ID-SMS'; AccessToken='AT-SMS'; RefreshToken='RT-SMS'; ExpiresIn=3600; NewDeviceMetadata=@{ DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='eu-west-1_GROUP' } } }
                        }
                    }
                    return MockResponse 400 @{ __type='x#InvalidParameterException'; message="unexpected $($req.ChallengeName)" }
                }
                'e2e/ConfirmDevice'      { return MockResponse 200 @{} }
                'e2e/UpdateDeviceStatus' { return MockResponse 200 @{} }
                'refresh-ok/InitiateAuth' {
                    if ($req.AuthFlow -ne 'REFRESH_TOKEN_AUTH') { return MockResponse 400 @{ __type='x#InvalidParameterException'; message='expected refresh' } }
                    if ($req.AuthParameters.DEVICE_KEY -ne 'eu-west-1_DEVKEY123') { return MockResponse 400 @{ __type='x#InvalidParameterException'; message='refresh must carry DEVICE_KEY' } }
                    return MockResponse 200 @{ AuthenticationResult=@{ IdToken='ID-REFRESHED'; AccessToken='AT-REFRESHED'; ExpiresIn=3600 } }
                }
                'refresh-dead/InitiateAuth' {
                    if ($req.AuthFlow -eq 'REFRESH_TOKEN_AUTH') { return MockResponse 400 @{ __type='x#NotAuthorizedException'; message='Invalid Refresh Token' } }
                    return MockResponse 200 @{ ChallengeName='PASSWORD_VERIFIER'; ChallengeParameters=$pvParams; Session='sess-1' }
                }
                'refresh-dead/RespondToAuthChallenge' {
                    if ($req.ChallengeName -eq 'PASSWORD_VERIFIER') { return MockResponse 200 @{ ChallengeName='SMS_MFA'; Session='sess-mfa'; ChallengeParameters=@{ CODE_DELIVERY_DESTINATION='+447*******45' } } }
                    return MockResponse 400 @{ __type='x#InvalidParameterException'; message='unexpected' }
                }
                'device-login/InitiateAuth' {
                    return MockResponse 200 @{ ChallengeName='PASSWORD_VERIFIER'; ChallengeParameters=$pvParams; Session='sess-1' }
                }
                'device-login/RespondToAuthChallenge' {
                    switch ($req.ChallengeName) {
                        'PASSWORD_VERIFIER' {
                            if ($req.ChallengeResponses.DEVICE_KEY -ne 'eu-west-1_DEVKEY123') { return MockResponse 200 @{ ChallengeName='SMS_MFA'; Session='sess-mfa'; ChallengeParameters=@{ CODE_DELIVERY_DESTINATION='+447*******45' } } }
                            return MockResponse 200 @{ ChallengeName='DEVICE_SRP_AUTH'; Session='sess-2' }
                        }
                        'DEVICE_SRP_AUTH' {
                            if (-not $req.ChallengeResponses.SRP_A -or -not $req.ChallengeResponses.DEVICE_KEY) { return MockResponse 400 @{ __type='x#InvalidParameterException'; message='device srp fields missing' } }
                            return MockResponse 200 @{ ChallengeName='DEVICE_PASSWORD_VERIFIER'; ChallengeParameters=$devParams; Session='sess-3' }
                        }
                        'DEVICE_PASSWORD_VERIFIER' {
                            if (-not $req.ChallengeResponses.PASSWORD_CLAIM_SIGNATURE) { return MockResponse 400 @{ __type='x#NotAuthorizedException'; message='no sig' } }
                            return MockResponse 200 @{ AuthenticationResult=@{ IdToken='ID-DEV'; AccessToken='AT-DEV'; ExpiresIn=3600; RefreshToken='RT-DEV' } }
                        }
                    }
                    return MockResponse 400 @{ __type='x#InvalidParameterException'; message="unexpected $($req.ChallengeName)" }
                }
            }
            return MockResponse 400 @{ __type='x#InvalidParameterException'; message="unmocked: $Scenario/$target" }
        }
        Mock -ModuleName PoSHive Invoke-WebRequest ($body.GetNewClosure())
    }

    BeforeEach {
        $script:CacheFile = Join-Path ([IO.Path]::GetTempPath()) ('poshive-e2e-' + [guid]::NewGuid().ToString('n') + '.json')
        $script:Caches += $script:CacheFile
        $script:State.Scenario = 'none'
        $script:Cred = [pscredential]::New('ME@Example.com', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
    }

    It 'parks the SMS challenge when headless (-NoPrompt)' {
        $script:State.Scenario = 'fresh-login'
        $r = Connect-Hive -Credential $script:Cred -NoPrompt -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'WaitingForSmsCode'
        $r.CodeDeliveryDestination | Should -Be '+447*******45'
        $r.Username | Should -Be 'me@example.com'
    }

    It 'completes a parked login with Complete-HiveLogin (registers + caches)' {
        $script:State.Scenario = 'e2e'
        $null = Connect-Hive -Credential $script:Cred -NoPrompt -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        { Complete-HiveLogin -Code '000000' -TokenCacheFile $script:CacheFile } |
            Should -Throw -ExpectedMessage 'CodeMismatchException*'
        $r = Complete-HiveLogin -Code '123456' -TokenCacheFile $script:CacheFile
        $r.Status | Should -Be 'Connected'
        $r.Username | Should -Be 'me@example.com'

        $disk = & $script:M { param($p) Get-HiveCachedDevice -Path $p } $script:CacheFile
        $disk.IdToken      | Should -Be 'ID-SMS'
        $disk.RefreshToken | Should -Be 'RT-SMS'
        $disk.DeviceKey    | Should -Be 'eu-west-1_DEVKEY123'
        $disk.DevicePassword | Should -Not -BeNullOrEmpty
        Get-Content $script:CacheFile -Raw | Should -Not -BeLike '*ID-SMS*'
    }

    It 'completes inline when -Otp is supplied with -NoPrompt' {
        $script:State.Scenario = 'e2e'
        $r = Connect-Hive -Credential $script:Cred -NoPrompt -Otp '123456' -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'Connected'
        $r.Path | Should -Be 'sms'
    }

    It 'reuses still-valid cached tokens without touching Cognito' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; PoolId=$script:PoolId; ClientId='cid'
            DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='eu-west-1_GROUP'; DevicePassword='dp'
            RefreshToken='RT'; IdToken='ID'; AccessToken='AT'
            TokenExpiresAtUtc=([datetime]::UtcNow.AddHours(1)).ToString('o')
        }
        # Scenario 'none' makes any Cognito call return InvalidParameterException.
        $r = Connect-Hive -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'Connected'
        $r.Path | Should -Be 'cached'
    }

    It 'silently refreshes when the cached token has expired' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; PoolId=$script:PoolId; ClientId='cid'
            DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='eu-west-1_GROUP'; DevicePassword='dp'
            RefreshToken='RT-SMS'; IdToken='ID'; AccessToken='AT'
            TokenExpiresAtUtc=([datetime]::UtcNow.AddMinutes(-1)).ToString('o')
        }
        $script:State.Scenario = 'refresh-ok'
        $r = Connect-Hive -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'Connected'
        $r.Path | Should -Be 'refresh'
        # the refresh token is kept (Cognito does not rotate it on refresh)
        $disk = & $script:M { param($p) Get-HiveCachedDevice -Path $p } $script:CacheFile
        $disk.RefreshToken | Should -Be 'RT-SMS'
        $disk.IdToken | Should -Be 'ID-REFRESHED'
    }

    It 'falls back to SMS when the refresh token is dead' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; PoolId=$script:PoolId; ClientId='cid'
            DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='eu-west-1_GROUP'; DevicePassword='dp'
            RefreshToken='RT-DEAD'; IdToken='ID'; AccessToken='AT'
            TokenExpiresAtUtc=([datetime]::UtcNow.AddMinutes(-1)).ToString('o')
        }
        $script:State.Scenario = 'refresh-dead'
        $r = Connect-Hive -Credential $script:Cred -NoPrompt -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'WaitingForSmsCode'
    }

    It 'logs in with the remembered device without SMS' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; PoolId=$script:PoolId; ClientId='cid'
            DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='eu-west-1_GROUP'; DevicePassword='dp'
        }
        $script:State.Scenario = 'device-login'
        $r = Connect-Hive -Credential $script:Cred -NoPrompt -TokenCacheFile $script:CacheFile -PoolId $script:PoolId -ClientId 'cid'
        $r.Status | Should -Be 'Connected'
        $r.Path | Should -Be 'device'
        $disk = & $script:M { param($p) Get-HiveCachedDevice -Path $p } $script:CacheFile
        $disk.IdToken | Should -Be 'ID-DEV'
        # device logins rotate to a brand-new refresh token
        $disk.RefreshToken | Should -Be 'RT-DEV'
    }
}

Describe 'Get-HiveAuthState / Disconnect-Hive' {
    BeforeEach {
        $script:CacheFile = Join-Path ([IO.Path]::GetTempPath()) ('poshive-e2e-' + [guid]::NewGuid().ToString('n') + '.json')
        $script:Caches += $script:CacheFile
    }

    It 'reports a fresh login is needed for an empty cache' {
        $st = Get-HiveAuthState -TokenCacheFile $script:CacheFile
        $st.NextSignIn | Should -BeLike 'fresh login*'
    }

    It 'reports device/refresh availability once cached' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; DeviceKey='eu-west-1_DEVKEY123'; DeviceGroupKey='gk'; DevicePassword='dp'
            RefreshToken='RT'; IdToken='ID'; AccessToken='AT'
            TokenExpiresAtUtc=([datetime]::UtcNow.AddHours(1)).ToString('o')
        }
        $st = Get-HiveAuthState -TokenCacheFile $script:CacheFile
        $st.Username | Should -Be 'me@example.com'
        $st.DeviceRegistered | Should -BeTrue
        $st.RefreshTokenPresent | Should -BeTrue
        $st.NextSignIn | Should -Be 'reuse cached tokens'
    }

    It 'Disconnect-Hive clears the local cache' {
        & $script:M { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $script:CacheFile @{
            Username='me@example.com'; DeviceKey='dk'; RefreshToken='RT'; IdToken='ID'; AccessToken='AT'
        }
        $null = Disconnect-Hive -TokenCacheFile $script:CacheFile
        Test-Path $script:CacheFile | Should -BeFalse
    }
}
