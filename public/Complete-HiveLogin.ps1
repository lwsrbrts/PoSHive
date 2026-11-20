function Complete-HiveLogin {
    <#
        .SYNOPSIS
        Supplies the SMS OTP code to a Hive login challenge parked by
        Connect-Hive -NoPrompt (headless two-step login).

        .DESCRIPTION
        Reads the parked challenge from the token cache (parked challenges
        expire with the Cognito session, ~15 minutes) and completes the
        SMS_MFA flow. On success the device is registered so future logins
        skip SMS, exactly as with an interactive Connect-Hive.

        .EXAMPLE
        Connect-Hive -Credential (Get-Credential) -NoPrompt
        Complete-HiveLogin -Code 123456
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Code,
        [switch]$NoTokenCache,
        [string]$TokenCacheFile
    )
    if ($NoTokenCache) {
        throw 'HiveNoPendingChallenge: -NoTokenCache was used, so no challenge could have been parked. Re-run Connect-Hive without -NoTokenCache.'
    }
    $cachePath = Get-HiveCachePath -Path $TokenCacheFile
    $pending = Get-HivePendingChallenge -Path $cachePath
    if (-not $pending) {
        throw 'HiveNoPendingChallenge: nothing to complete (no parked challenge, or it expired). Run Connect-Hive -NoPrompt again to receive a new SMS.'
    }
    $result = Complete-HiveOtpLogin -Pending $pending -Code $Code -CachePath $cachePath -UseCache $true
    return [pscustomobject]@{
        Status   = 'Connected'
        Path     = $result.Path
        Message  = $result.Message
        Username = $pending['Username']
        Expires  = $result.Device['TokenExpiresAtUtc']
    }
}
