function Disconnect-Hive {
    <#
        .SYNOPSIS
        Clears the local Hive session/cache.

        .DESCRIPTION
        Removes the cached tokens and (optionally) unregisters the device
        with Cognito. Without -ForgetDevice the next Connect-Hive can still
        log in silently with the remembered device (a password will be
        needed). With -ForgetDevice the device is deleted server-side, so
        the next login requires a fresh SMS code.

        .PARAMETER ForgetDevice
        Also call Cognito ForgetDevice and remove the device registration.

        .PARAMETER AccessToken
        Token used for ForgetDevice. Defaults to the cached access token
        when still present (it may already be expired; a fresh
        Connect-Hive may be required for this option to work).

        .EXAMPLE
        Disconnect-Hive
        Disconnect-Hive -ForgetDevice
    #>
    [CmdletBinding()]
    param(
        [switch]$ForgetDevice,
        [string]$AccessToken,
        [string]$TokenCacheFile
    )
    $cachePath = Get-HiveCachePath -Path $TokenCacheFile
    $device = Get-HiveCachedDevice -Path $cachePath
    if (-not $device) {
        return [pscustomobject]@{ Status = 'Disconnected'; Message = 'No cached Hive session was present.' }
    }

    $forgot = $false
    if ($ForgetDevice -and $device['DeviceKey']) {
        $token = if ($AccessToken) { $AccessToken } else { $device['AccessToken'] }
        if ($token) {
            $Region = Get-HiveRegionFromPoolId ($device['PoolId'] ?? 'eu-west-1_x')
            Try {
                $null = Forget-HiveCognitoDevice -Region $Region -AccessToken $token -DeviceKey $device['DeviceKey']
                $forgot = $true
            } Catch {
                Write-Warning "PoSHive: ForgetDevice failed ($($_.Exception.Message)). The device stays registered server-side until the token it was issued for expires or you sign in and retry."
            }
        } else {
            Write-Warning 'PoSHive: no access token available for ForgetDevice; clearing local cache only.'
        }
    }

    Clear-HiveCache -Path $cachePath
    [pscustomobject]@{
        Status      = 'Disconnected'
        ForgetDevice = $forgot
        Message     = if ($ForgetDevice) {
            if ($forgot) { 'Hive session cleared and device forgotten (future logins will require SMS).' }
            else { 'Hive session cleared; device NOT forgotten (silent device login may still work).' }
        } else {
            'Hive session cleared locally; device remains registered so future logins can skip SMS.'
        }
    }
}
