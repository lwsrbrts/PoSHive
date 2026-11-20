function Get-HiveAuthState {
    <#
        .SYNOPSIS
        Shows what Connect-Hive would do next, without contacting Hive
        (except a scrape of sso.hivehome.com if the pool id is unknown).

        .EXAMPLE
        Get-HiveAuthState
    #>
    [CmdletBinding()]
    param([string]$TokenCacheFile)
    $cachePath = Get-HiveCachePath -Path $TokenCacheFile
    $device = Get-HiveCachedDevice -Path $cachePath
    $pending = Get-HivePendingChallenge -Path $cachePath

    $next = 'fresh login (username/password + SMS OTP)'
    if ($pending) {
        $next = "complete parked SMS challenge: Complete-HiveLogin -Code <code> (sent to $($pending['CodeDeliveryDestination']))"
    }
    elseif ($device) {
        if (Get-HiveCachedTokenUsable -Device $device) { $next = 'reuse cached tokens' }
        elseif ($device['RefreshToken']) { $next = 'silent refresh (REFRESH_TOKEN_AUTH)' }
        elseif ($device['DeviceKey'] -and $device['DevicePassword']) { $next = 'device login (password required, no SMS)' }
    }

    $props = [ordered]@{
        CacheFile   = $cachePath
        CacheExists = (Test-Path -LiteralPath $cachePath)
        Username    = if ($device) { $device['Username'] } else { $null }
        DeviceRegistered = [bool]($device -and $device['DeviceKey'] -and $device['DevicePassword'])
        RefreshTokenPresent = [bool]($device -and $device['RefreshToken'])
        TokensValid = [bool](Get-HiveCachedTokenUsable -Device $device)
        TokenExpiresAtUtc = if ($device) { $device['TokenExpiresAtUtc'] } else { $null }
        PendingSmsChallenge = [bool]$pending
        PendingCodeDestination = if ($pending) { $pending['CodeDeliveryDestination'] } else { $null }
        NextSignIn  = $next
    }
    return [pscustomobject]$props
}
