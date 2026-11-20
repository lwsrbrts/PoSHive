function Connect-Hive {
    <#
        .SYNOPSIS
        Authenticates to Hive (British Gas) and caches the session.

        .DESCRIPTION
        Resolves authentication in this order:
          1. cached tokens still valid           -> reused as-is
          2. cached refresh token (+device key)  -> silent token renewal
          3. remembered-device SRP login         -> silent, no SMS
          4. fresh username/password login       -> SMS OTP (this cmdlet,
             or Complete-HiveLogin when headless)

        After a successful SMS login the device is registered with Cognito
        ("remembered"), so steps 2-3 make future SMS codes rare.

        .PARAMETER Credential
        PSCredential holding the Hive username and password.

        .PARAMETER Username
        Hive username (email). Required only when no credential is supplied
        and a cached/refresh-only login is not possible.

        .PARAMETER Otp
        SMS one-time code, when supplied alongside the SMS challenge. Without
        it the code is prompted for (unless -NoPrompt).

        .PARAMETER NoPrompt
        Never prompt. If SMS is required, the challenge is parked (about 15
        minutes) and this cmdlet returns instructions to finish with
        Complete-HiveLogin -Code 123456.

        .PARAMETER NoTokenCache
        Do not read or write the token/device cache for this call.

        .PARAMETER TokenCacheFile
        Override the cache location (default $env:USERPROFILE\.poshive\hive-device.json).

        .PARAMETER AuthFlow
        Cognito auth flow for fresh logins. Default USER_SRP_AUTH (supported).
        USER_PASSWORD_AUTH is an opt-in probe only - not verified against Hive.

        .PARAMETER Force
        Ignore cached tokens and perform a fresh login.

        .EXAMPLE
        Connect-Hive -Credential (Get-Credential)

        .EXAMPLE
        Connect-Hive -Credential (Get-Credential) -NoPrompt
        # then, once the SMS arrives:
        Complete-HiveLogin -Code 123456
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    param(
        [Parameter(ParameterSetName = 'Credential')][pscredential]$Credential,
        [Parameter(ParameterSetName = 'Username')][string]$Username,
        [string]$Otp,
        [switch]$NoPrompt,
        [switch]$NoTokenCache,
        [string]$TokenCacheFile,
        [ValidateSet('USER_SRP_AUTH', 'USER_PASSWORD_AUTH')][string]$AuthFlow = 'USER_SRP_AUTH',
        [switch]$Force,
        [string]$PoolId,
        [string]$ClientId
    )
    $cachePath = Get-HiveCachePath -Path $TokenCacheFile
    $useCache = -not $NoTokenCache

    # --- resolve username ----------------------------------------------------
    if ($Credential) {
        $Username = $Credential.GetNetworkCredential().UserName
    }
    if (-not $Username -and $useCache) {
        $cached = Get-HiveCachedDevice -Path $cachePath
        if ($cached) { $Username = $cached['Username'] }
    }
    if (-not $Username) {
        throw 'HiveCredentialRequired: supply -Credential (or -Username with a cached session).'
    }
    $Username = Normalize-HiveUsername $Username

    # --- resolve password (only needed for device/fresh logins) --------------
    $password = $null
    if ($Credential) { $password = $Credential.GetNetworkCredential().Password }

    function Request-HivePassword {
        if ($password) { return $password }
        if ($NoPrompt) { throw 'HiveCredentialRequired: -Credential is needed for a fresh login and -NoPrompt was set.' }
        $secure = Read-Host -Prompt "Hive password for $Username" -AsSecureString
        return [Net.NetworkCredential]::new('', $secure).Password
    }

    # First pass may succeed from cache/refresh without any password; if the
    # engine needs credentials, prompt (unless headless) and retry once.
    $resolved = $null
    try {
        $resolved = Resolve-HiveAuth -Username $Username -Password $password -CachePath $cachePath `
            -UseCache $useCache -PoolId $PoolId -ClientId $ClientId -AuthFlow $AuthFlow -Force:$Force
    } catch {
        if ($_.Exception.Message -like 'HiveCredentialRequired*' -and -not $NoPrompt) {
            $password = Request-HivePassword
            $resolved = Resolve-HiveAuth -Username $Username -Password $password -CachePath $cachePath `
                -UseCache $useCache -PoolId $PoolId -ClientId $ClientId -AuthFlow $AuthFlow -Force:$Force
        } else { throw }
    }

    if (-not $resolved.NeedsOtp) {
        return [pscustomobject]@{
            Status   = 'Connected'
            Path     = $resolved.Result.Path
            Message  = $resolved.Result.Message
            Username = $Username
            Expires  = $resolved.Result.Device['TokenExpiresAtUtc']
        }
    }

    # --- SMS OTP required ------------------------------------------------------
    $pending = $resolved.Challenge
    if ($NoPrompt -and -not $Otp) {
        return [pscustomobject]@{
            Status                = 'WaitingForSmsCode'
            Username              = $Username
            CodeDeliveryDestination = $pending['CodeDeliveryDestination']
            Message               = "An SMS code was sent to $($pending['CodeDeliveryDestination']). Finish with: Complete-HiveLogin -Code 123456 (valid ~15 minutes)."
        }
    }

    $otpValue = $Otp
    for ($try = 1; $try -le 3; $try++) {
        if (-not $otpValue) {
            if ($NoPrompt) {
                throw "HiveOtpRequired: SMS code needed for $($pending['CodeDeliveryDestination']). Finish with: Complete-HiveLogin -Code 123456 (valid ~15 minutes)."
            }
            $otpValue = Read-Host -Prompt "Enter the Hive SMS code sent to $($pending['CodeDeliveryDestination'])"
        }
        Try {
            $result = Complete-HiveOtpLogin -Pending $pending -Code $otpValue -CachePath $cachePath -UseCache $useCache
            return [pscustomobject]@{
                Status   = 'Connected'
                Path     = $result.Path
                Message  = $result.Message
                Username = $Username
                Expires  = $result.Device['TokenExpiresAtUtc']
            }
        } Catch {
            $msg = $_.Exception.Message
            if ($msg -like 'CodeMismatchException*' -and $try -lt 3) {
                Write-Warning "Incorrect code ($try of 3). $msg"
                $otpValue = $null
                continue
            }
            if ($msg -like 'CodeMismatchException*') {
                throw "HiveOtpFailed: three incorrect codes. Run Connect-Hive again to receive a new SMS."
            }
            throw   # NotAuthorizedException / ExpiredCodeException / network: surface
        }
    }
}
