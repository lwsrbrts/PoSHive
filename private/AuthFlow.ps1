# Auth-flow orchestration: the logic behind Connect-Hive / Complete-HiveLogin.
# Resolution order (per approved plan):
#   cached valid IdToken -> REFRESH_TOKEN_AUTH(+DEVICE_KEY) -> device SRP login
#   -> fresh SRP login (+SMS_MFA).
# Mirrors Pyhass/Pyhive control flow; see private/Cognito.ps1 + private/Srp.ps1.

$script:HiveDeviceName = 'PoSHive'

function Normalize-HiveUsername {
    param([Parameter(Mandatory)][string]$Username)
    # The Hive pool is case-sensitive (pyhive comment); trim + lowercase.
    Return $Username.Trim().ToLowerInvariant()
}

function New-HiveAuthResult {
    # Shape shared by every success path returned to public cmdlets.
    param(
        [Parameter(Mandatory)][hashtable]$Device,
        [string]$Path,          # cached|refresh|device|password
        [string]$Message
    )
    Return [pscustomobject]@{
        Path    = $Path
        Message = $Message
        Device  = $Device
    }
}

function Update-HiveDeviceFromAuth {
    # Merge an AuthenticationResult into the device record + expiry stamp.
    param(
        [Parameter(Mandatory)][hashtable]$Device,
        [Parameter(Mandatory)][psobject]$AuthResult
    )
    $Device['IdToken']     = $AuthResult.IdToken
    $Device['AccessToken'] = $AuthResult.AccessToken
    If ($AuthResult.RefreshToken) { $Device['RefreshToken'] = $AuthResult.RefreshToken }
    $expiresIn = if ($AuthResult.ExpiresIn) { [int]$AuthResult.ExpiresIn } else { 3600 }
    $Device['TokenExpiresAtUtc'] = ([datetime]::UtcNow.AddSeconds($expiresIn)).ToString('o')
    If ($AuthResult.NewDeviceMetadata) {
        If ($AuthResult.NewDeviceMetadata.DeviceKey) { $Device['DeviceKey'] = $AuthResult.NewDeviceMetadata.DeviceKey }
        If ($AuthResult.NewDeviceMetadata.DeviceGroupKey) { $Device['DeviceGroupKey'] = $AuthResult.NewDeviceMetadata.DeviceGroupKey }
    }
    Return $Device
}

function Start-HiveSrpHandshake {
    # Step 1: InitiateAuth USER_SRP_AUTH (or the USER_PASSWORD_AUTH probe).
    # Returns the raw Cognito response; caller branches on ChallengeName.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [string]$DeviceKey,
        [ValidateSet('USER_SRP_AUTH', 'USER_PASSWORD_AUTH')][string]$AuthFlow = 'USER_SRP_AUTH'
    )
    $params = @{ Region = $Region; ClientId = $ClientId; AuthFlow = $AuthFlow }
    If ($AuthFlow -eq 'USER_SRP_AUTH') {
        $ephemeral = New-HiveSrpEphemeral
        $params['AuthParameters'] = @{ USERNAME = $Username; SRP_A = $ephemeral.HexA }
    } Else {
        $params['AuthParameters'] = @{ USERNAME = $Username; PASSWORD = $Password }
    }
    $response = Start-HiveCognitoAuth @params
    $result = @{
        Response   = $response
        Ephemeral  = if ($ephemeral) { $ephemeral } else { $null }
        Password   = $Password
        Username   = $Username
        DeviceKey  = $DeviceKey
    }
    Return $result
}

function Send-HivePasswordClaim {
    # Step 2: RespondToAuthChallenge PASSWORD_VERIFIER. SRP maths computed
    # immediately before sending (AWS expects a prompt response).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PoolId,
        [Parameter(Mandatory)]$Handshake,   # from Start-HiveSrpHandshake
        [switch]$IncludeSession
    )
    $resp = $Handshake.Response
    $cp = $resp.ChallengeParameters
    $userId = [string]$cp.USER_ID_FOR_SRP
    If (-not $userId) { $userId = $Handshake.Username }

    $hkdf = Get-HivePasswordHkdf -SmallA $Handshake.Ephemeral.SmallA -LargeA $Handshake.Ephemeral.LargeA `
        -UserId $userId -Password $Handshake.Password -PoolId $PoolId `
        -SrpBHex ([string]$cp.SRP_B) -SaltHex ([string]$cp.SALT)
    $timestamp = Get-HiveCognitoTimestamp
    $signature = Get-HivePasswordClaimSignature -Hkdf $hkdf.Hkdf -PoolId $PoolId -UserId $userId `
        -SecretBlockB64 ([string]$cp.SECRET_BLOCK) -Timestamp $timestamp

    $challengeResponses = @{
        USERNAME                   = $userId
        TIMESTAMP                  = $timestamp
        PASSWORD_CLAIM_SECRET_BLOCK = ([string]$cp.SECRET_BLOCK)
        PASSWORD_CLAIM_SIGNATURE   = $signature
    }
    If ($Handshake.DeviceKey) { $challengeResponses['DEVICE_KEY'] = $Handshake.DeviceKey }

    $session = if ($IncludeSession -and $resp.Session) { [string]$resp.Session } else { $null }
    $next = $null
    If ($session) {
        Try {
            $next = Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
                -ChallengeName 'PASSWORD_VERIFIER' -ChallengeResponses $challengeResponses -Session $session
        } Catch {
            # Session handling on PASSWORD_VERIFIER is untested against Hive's
            # pool; pyhive omits it, so retry once without.
            Write-Verbose "PoSHive: PASSWORD_VERIFIER with Session failed ($($_.Exception.Message)); retrying without."
            $next = Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
                -ChallengeName 'PASSWORD_VERIFIER' -ChallengeResponses $challengeResponses
        }
    } Else {
        $next = Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
            -ChallengeName 'PASSWORD_VERIFIER' -ChallengeResponses $challengeResponses
    }
    If ($next) { $next | Add-Member -NotePropertyName UserId -NotePropertyValue $userId -Force }
    Return $next
}

function Send-HiveDeviceSrpClaim {
    # Step 5a: respond to DEVICE_SRP_AUTH with a *fresh* SRP_A (pyhive does).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)]$Challenge,        # the DEVICE_SRP_AUTH response
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$DeviceKey,
        [Parameter(Mandatory)][string]$DeviceGroupKey,
        [Parameter(Mandatory)][string]$DevicePassword
    )
    $ephemeral = New-HiveSrpEphemeral
    $next = Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
        -ChallengeName 'DEVICE_SRP_AUTH' -ChallengeResponses @{
            USERNAME = $Username
            DEVICE_KEY = $DeviceKey
            SRP_A    = $ephemeral.HexA
        }
    $cp = $next.ChallengeParameters
    If ($next.ChallengeName -ne 'DEVICE_PASSWORD_VERIFIER') { Return $next }

    $hkdf = Get-HiveDeviceHkdf -SmallA $ephemeral.SmallA -LargeA $ephemeral.LargeA `
        -DeviceGroupKey $DeviceGroupKey -DeviceKey $DeviceKey -DevicePassword $DevicePassword `
        -SrpBHex ([string]$cp.SRP_B) -SaltHex ([string]$cp.SALT)
    $timestamp = Get-HiveCognitoTimestamp
    $signature = Get-HiveDeviceClaimSignature -Hkdf $hkdf.Hkdf -DeviceGroupKey $DeviceGroupKey `
        -DeviceKey $DeviceKey -SecretBlockB64 ([string]$cp.SECRET_BLOCK) -Timestamp $timestamp

    Return Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
        -ChallengeName 'DEVICE_PASSWORD_VERIFIER' -ChallengeResponses @{
            USERNAME                    = $Username
            DEVICE_KEY                  = $DeviceKey
            TIMESTAMP                   = $timestamp
            PASSWORD_CLAIM_SECRET_BLOCK = ([string]$cp.SECRET_BLOCK)
            PASSWORD_CLAIM_SIGNATURE    = $signature
        }
}

function Register-HiveDevice {
    # Step 4: ConfirmDevice + UpdateDeviceStatus(remembered). Failure here is
    # not fatal for the current session (tokens are already valid); it just
    # means the next login will need SMS again, so warn rather than throw.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$DeviceKey,
        [Parameter(Mandatory)][string]$DeviceGroupKey
    )
    Try {
        $verifier = New-HiveDeviceSecretVerifierConfig -DeviceGroupKey $DeviceGroupKey -DeviceKey $DeviceKey
        $null = Set-HiveCognitoDeviceConfirmed -Region $Region -AccessToken $AccessToken `
            -DeviceKey $DeviceKey -DeviceName $script:HiveDeviceName `
            -PasswordVerifierB64 $verifier.PasswordVerifierB64 -SaltB64 $verifier.SaltB64
        $null = Update-HiveCognitoDeviceStatus -Region $Region -AccessToken $AccessToken `
            -DeviceKey $DeviceKey -Status 'remembered'
        Return $verifier.DevicePassword
    } Catch {
        Write-Warning "PoSHive: device registration failed ($($_.Exception.Message)); next login will require SMS again."
        Return $null
    }
}

function Connect-HiveByRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][hashtable]$Device
    )
    If (-not $Device['RefreshToken']) { throw 'HiveNoRefreshToken: no cached refresh token.' }
    $authParams = @{ REFRESH_TOKEN = $Device['RefreshToken'] }
    If ($Device['DeviceKey']) { $authParams['DEVICE_KEY'] = $Device['DeviceKey'] }
    $response = Start-HiveCognitoAuth -Region $Region -ClientId $ClientId `
        -AuthFlow 'REFRESH_TOKEN_AUTH' -AuthParameters $authParams
    If (-not $response -or -not $response.AuthenticationResult -or -not $response.AuthenticationResult.IdToken) {
        throw 'HiveRefreshFailed: Cognito returned no AuthenticationResult for REFRESH_TOKEN_AUTH.'
    }
    Return $response.AuthenticationResult
}

function Connect-HiveByDevice {
    # Full device-SRP login (no SMS). Throws when the device is no longer
    # remembered (Cognito answers SMS_MFA or NotAuthorizedException).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PoolId,
        [Parameter(Mandatory)][hashtable]$Device,
        [Parameter(Mandatory)][string]$Password
    )
    $hs = Start-HiveSrpHandshake -Region $Region -ClientId $ClientId -Username $Device['Username'] `
        -Password $Password -DeviceKey $Device['DeviceKey']
    If ($hs.Response.ChallengeName -ne 'PASSWORD_VERIFIER') {
        throw "HiveDeviceLoginRejected: unexpected challenge $($hs.Response.ChallengeName) before password claim."
    }
    $next = Send-HivePasswordClaim -Region $Region -ClientId $ClientId -PoolId $PoolId -Handshake $hs
    If ($next.ChallengeName -ne 'DEVICE_SRP_AUTH') {
        If ($next.ChallengeName -eq 'SMS_MFA') { throw 'HiveDeviceLoginRejected: device no longer remembered (SMS required).' }
        throw "HiveDeviceLoginRejected: unexpected challenge $($next.ChallengeName)."
    }
    $final = Send-HiveDeviceSrpClaim -Region $Region -ClientId $ClientId -Challenge $next `
        -Username $Device['Username'] -DeviceKey $Device['DeviceKey'] `
        -DeviceGroupKey $Device['DeviceGroupKey'] -DevicePassword $Device['DevicePassword']
    If ($final.AuthenticationResult) { Return $final.AuthenticationResult }
    If ($final.ChallengeName -eq 'SMS_MFA') { throw 'HiveDeviceLoginRejected: device no longer remembered (SMS required).' }
    throw "HiveDeviceLoginRejected: unexpected challenge $($final.ChallengeName) after DEVICE_PASSWORD_VERIFIER."
}

function Start-HiveFreshLogin {
    # Steps 1-2 of a full login; returns either an authentication result
    # (rare: no MFA configured) or the SMS_MFA challenge to be completed.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PoolId,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [string]$DeviceKey,
        [ValidateSet('USER_SRP_AUTH', 'USER_PASSWORD_AUTH')][string]$AuthFlow = 'USER_SRP_AUTH'
    )
    $hs = Start-HiveSrpHandshake -Region $Region -ClientId $ClientId -Username $Username `
        -Password $Password -DeviceKey $DeviceKey -AuthFlow $AuthFlow
    If ($AuthFlow -eq 'USER_PASSWORD_AUTH') {
        # Probe flow: either authenticated outright or a new-password/etc
        # challenge we deliberately do not chase (SRP remains the supported path).
        If ($hs.Response.AuthenticationResult) { Return [pscustomobject]@{ AuthenticationResult = $hs.Response.AuthenticationResult; Challenge = $null } }
        throw "HiveAuthFlowUnsupported: USER_PASSWORD_AUTH returned challenge '$($hs.Response.ChallengeName)'. Use the default -AuthFlow USER_SRP_AUTH."
    }
    If ($hs.Response.ChallengeName -ne 'PASSWORD_VERIFIER') {
        throw "HiveAuthError: InitiateAuth returned challenge '$($hs.Response.ChallengeName)' instead of PASSWORD_VERIFIER."
    }
    $next = Send-HivePasswordClaim -Region $Region -ClientId $ClientId -PoolId $PoolId -Handshake $hs -IncludeSession
    Return [pscustomobject]@{ AuthenticationResult = $next.AuthenticationResult; Challenge = $next }
}

function Complete-HiveSmsChallenge {
    # Step 3: send SMS_MFA_CODE against a parked (or in-memory) session.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Session,
        [Parameter(Mandatory)][string]$Code
    )
    Return Complete-HiveCognitoChallenge -Region $Region -ClientId $ClientId `
        -ChallengeName 'SMS_MFA' -Session $Session -ChallengeResponses @{
            USERNAME     = $Username
            SMS_MFA_CODE = $Code.Trim()
        }
}

function Complete-HiveOtpLogin {
    # Finish a parked (or in-flight) SMS_MFA challenge: send the code, build
    # the device record, register the device so future logins skip SMS, and
    # persist. Shared by Connect-Hive (interactive) and Complete-HiveLogin
    # (headless). Throws the raw Cognito error for wrong/expired codes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Pending,   # Username/Session/PoolId/ClientId
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$CachePath,
        [bool]$UseCache = $true
    )
    $Region = Get-HiveRegionFromPoolId $Pending['PoolId']
    $response = Complete-HiveSmsChallenge -Region $Region -ClientId $Pending['ClientId'] `
        -Username $Pending['Username'] -Session $Pending['Session'] -Code $Code
    If (-not $response -or -not $response.AuthenticationResult -or -not $response.AuthenticationResult.IdToken) {
        throw 'HiveAuthError: SMS challenge did not return an AuthenticationResult.'
    }
    If ($UseCache) { Clear-HivePendingChallenge -Path $CachePath }

    $device = @{
        Username = $Pending['Username']
        PoolId   = $Pending['PoolId']
        ClientId = $Pending['ClientId']
    }
    $device = Update-HiveDeviceFromAuth -Device $device -AuthResult $response.AuthenticationResult
    If ($device['DeviceKey'] -and $device['DeviceGroupKey'] -and $device['AccessToken']) {
        $dp = Register-HiveDevice -Region $Region -AccessToken $device['AccessToken'] `
            -DeviceKey $device['DeviceKey'] -DeviceGroupKey $device['DeviceGroupKey']
        If ($dp) { $device['DevicePassword'] = $dp }
    }
    If ($UseCache) { Set-HiveCachedDevice -Path $CachePath -Device $device }
    Return New-HiveAuthResult -Device $device -Path 'sms' -Message 'Hive login completed with SMS code; device registered for future logins.'
}

function Resolve-HiveAuth {
    # The resolution-order orchestrator used by Connect-Hive.
    # Returns @{ Result = <NewHiveAuthResult-shaped>; NeedsOtp = <bool>;
    #           Challenge = <sms challenge hashtable> } - never prompts itself.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Username,
        [string]$Password,
        [Parameter(Mandatory)][string]$CachePath,
        [bool]$UseCache = $true,
        [string]$PoolId,
        [string]$ClientId,
        [ValidateSet('USER_SRP_AUTH', 'USER_PASSWORD_AUTH')][string]$AuthFlow = 'USER_SRP_AUTH',
        [switch]$Force
    )
    $Username = Normalize-HiveUsername $Username

    If (-not $PoolId -or -not $ClientId) {
        $endpoints = Get-HiveCognitoEndpoints
        If (-not $PoolId) { $PoolId = $endpoints.PoolId }
        If (-not $ClientId) { $ClientId = $endpoints.ClientId }
    }
    $Region = Get-HiveRegionFromPoolId $PoolId

    $device = $null
    If ($UseCache) { $device = Get-HiveCachedDevice -Path $CachePath -Username $Username }

    If (-not $Force) {
        # 1) cached token still valid?
        If ($device -and (Get-HiveCachedTokenUsable -Device $device)) {
            Return @{ NeedsOtp = $false; Result = (New-HiveAuthResult -Device $device -Path 'cached' -Message 'Using cached Hive tokens.') }
        }
        # 2) refresh token (+DEVICE_KEY) - no password needed
        If ($device -and $device['RefreshToken']) {
            Try {
                $auth = Connect-HiveByRefresh -Region $Region -ClientId $ClientId -Device $device
                $device = Update-HiveDeviceFromAuth -Device $device -AuthResult $auth
                If ($UseCache) { Set-HiveCachedDevice -Path $CachePath -Device $device }
                Return @{ NeedsOtp = $false; Result = (New-HiveAuthResult -Device $device -Path 'refresh' -Message 'Hive tokens refreshed.') }
            } Catch {
                Write-Verbose "PoSHive: refresh failed ($($_.Exception.Message)); falling back to interactive login."
            }
        }
        # 3) device SRP login - needs the password to bootstrap the handshake
        If ($device -and $device['DeviceKey'] -and $device['DevicePassword'] -and $Password) {
            Try {
                $auth = Connect-HiveByDevice -Region $Region -ClientId $ClientId -PoolId $PoolId -Device $device -Password $Password
                $device = Update-HiveDeviceFromAuth -Device $device -AuthResult $auth
                If ($UseCache) { Set-HiveCachedDevice -Path $CachePath -Device $device }
                Return @{ NeedsOtp = $false; Result = (New-HiveAuthResult -Device $device -Path 'device' -Message 'Hive device login succeeded (no SMS).') }
            } Catch {
                If ($_.Exception.Message -like 'HiveDeviceLoginRejected*') {
                    Write-Verbose "PoSHive: ($($_.Exception.Message)); clearing device record."
                    $device.Remove('DeviceKey'); $device.Remove('DevicePassword')
                }
                Write-Verbose "PoSHive: device login failed ($($_.Exception.Message)); falling back to SMS login."
            }
        }
    }

    # 4) fresh SRP login (+SMS OTP)
    If (-not $Password) { throw 'HiveCredentialRequired: no valid cached session and no -Credential/-Password supplied.' }
    $start = Start-HiveFreshLogin -Region $Region -ClientId $ClientId -PoolId $PoolId `
        -Username $Username -Password $Password -AuthFlow $AuthFlow
    If ($start.AuthenticationResult) {
        # Rare: no MFA challenge at all.
        $device = @{ Username = $Username; PoolId = $PoolId; ClientId = $ClientId }
        $device = Update-HiveDeviceFromAuth -Device $device -AuthResult $start.AuthenticationResult
        If ($device['DeviceKey'] -and $device['DeviceGroupKey'] -and $device['AccessToken']) {
            $dp = Register-HiveDevice -Region $Region -AccessToken $device['AccessToken'] -DeviceKey $device['DeviceKey'] -DeviceGroupKey $device['DeviceGroupKey']
            If ($dp) { $device['DevicePassword'] = $dp }
        }
        If ($UseCache) { Set-HiveCachedDevice -Path $CachePath -Device $device }
        Return @{ NeedsOtp = $false; Result = (New-HiveAuthResult -Device $device -Path 'password' -Message 'Hive login succeeded (no MFA challenge issued).') }
    }

    $challenge = $start.Challenge
    If ($challenge.ChallengeName -ne 'SMS_MFA') {
        throw "HiveAuthError: unexpected challenge '$($challenge.ChallengeName)' after password claim."
    }
    $pending = @{
        Username              = $Username
        Session               = [string]$challenge.Session
        PoolId                = $PoolId
        ClientId              = $ClientId
        CodeDeliveryDestination = [string]$challenge.ChallengeParameters.CODE_DELIVERY_DESTINATION
    }
    If ($UseCache) { Set-HivePendingChallenge -Path $CachePath -Pending $pending }
    Return @{ NeedsOtp = $true; Challenge = $pending; PendingPassword = $Password }
}
