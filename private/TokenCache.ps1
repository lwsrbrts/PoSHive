# Persistent cache for PoSHive: the registered device record, the current
# token set, and any parked SMS_MFA challenge. One JSON file (default
# $env:USERPROFILE\.poshive\hive-device.json) holding two records:
#   device  - DeviceKey/DeviceGroupKey/DevicePassword/RefreshToken + tokens
#   pending - parked Cognito session awaiting an OTP code (15 min TTL)
# Values are encrypted at rest with Windows DPAPI (CurrentUser scope) when
# the platform provides it; otherwise plaintext JSON + a one-off warning.

$script:HiveCacheWarningShown = $false
$script:HivePendingTtlMinutes = 14   # Cognito sessions live ~15 min
$script:HiveTokenSkewSeconds = 60    # treat tokens as expired a minute early

function Get-HiveCachePath {
    [CmdletBinding()]
    param([string]$Path)
    If ($Path) { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
    Return (Join-Path (Join-Path $userHome '.poshive') 'hive-device.json')
}

function Test-HiveDpapiAvailable {
    Try {
        $bytes = [Text.Encoding]::UTF8.GetBytes('poshive')
        $null = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
        Return $true
    } Catch { Return $false }
}

function Protect-HiveSecretString {
    param([Parameter(Mandatory)][string]$PlainText)
    If (Test-HiveDpapiAvailable) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
        $protected = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
        Return [pscustomobject]@{ Encrypted = 'dpapi-currentuser'; Data = [Convert]::ToBase64String($protected) }
    }
    If (-not $script:HiveCacheWarningShown) {
        Write-Warning 'PoSHive: DPAPI unavailable on this platform - the token cache will be stored as PLAINTEXT JSON. Keep the cache file private (chmod 600) or use -NoTokenCache.'
        $script:HiveCacheWarningShown = $true
    }
    Return [pscustomobject]@{ Encrypted = 'none'; Data = $PlainText }
}

function Unprotect-HiveSecretString {
    param([Parameter(Mandatory)][psobject]$Envelope)
    If ($Envelope.Encrypted -eq 'dpapi-currentuser') {
        $protected = [Convert]::FromBase64String($Envelope.Data)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protected, $null, 'CurrentUser')
        Return [Text.Encoding]::UTF8.GetString($bytes)
    }
    Return [string]$Envelope.Data
}

function Read-HiveCacheFile {
    # Returns the raw cache hashtable from disk, or $null when absent or
    # unreadable (a corrupt cache must never brick the module - callers
    # treat it as "log in again").
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    If (-not (Test-Path -LiteralPath $Path)) { return $null }
    Try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        If (-not $raw) { return $null }
        Return (ConvertFrom-Json $raw -AsHashtable)
    } Catch {
        Write-Warning "PoSHive: could not read token cache '$Path' ($($_.Exception.Message)); ignoring it."
        Return $null
    }
}

function Write-HiveCacheFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][hashtable]$Device,
        [Parameter()][hashtable]$Pending
    )
    $dir = Split-Path -Parent $Path
    If ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $record = @{}
    If ($Device) {
        $record['device'] = (Protect-HiveSecretString (ConvertTo-Json $Device -Depth 10 -Compress))
    }
    If ($Pending) {
        $record['pending'] = (Protect-HiveSecretString (ConvertTo-Json $Pending -Depth 10 -Compress))
    }
    If (-not $record.Count) {
        If (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        return
    }
    $json = ConvertTo-Json $record -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8NoBOM
}

function Get-HiveCachedDevice {
    # Returns the device record hashtable (with decrypted content) or $null.
    # A record for a *different* username is treated as absent.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Username)
    $file = Read-HiveCacheFile -Path $Path
    If (-not $file -or -not $file['device']) { return $null }
    Try {
        $device = ConvertFrom-Json (Unprotect-HiveSecretString $file['device']) -AsHashtable
    } Catch {
        Write-Warning 'PoSHive: token cache device record unreadable; a fresh login is required.'
        return $null
    }
    If ($Username -and $device['Username'] -and $device['Username'] -ne $Username) { return $null }
    Return $device
}

function Set-HiveCachedDevice {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter()][hashtable]$Device)
    $file = Read-HiveCacheFile -Path $Path
    $pending = if ($file) { $file['pending'] } else { $null }
    Write-HiveCacheFile -Path $Path -Device $Device -Pending $pending
}

function Get-HivePendingChallenge {
    # Returns the parked challenge hashtable, or $null if none/parked too long.
    # Expired pending state is purged from the file as a side effect.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file = Read-HiveCacheFile -Path $Path
    If (-not $file -or -not $file['pending']) { return $null }
    Try {
        $pending = ConvertFrom-Json (Unprotect-HiveSecretString $file['pending']) -AsHashtable
    } Catch { $pending = $null }
    If (-not $pending) {
        # Unreadable/expired-shape pending: rewrite file without it.
        $devRaw = if ($file['device']) { $file['device'] } else { $null }
        If ($devRaw) {
            $device = ConvertFrom-Json (Unprotect-HiveSecretString $devRaw) -AsHashtable
            Write-HiveCacheFile -Path $Path -Device $device -Pending $null
        } Else {
            Clear-HiveCache -Path $Path
        }
        return $null
    }
    $parked = [datetime]::SpecifyKind([datetime]$pending['ParkedAtUtc'], 'Utc')
    If (([datetime]::UtcNow - $parked).TotalMinutes -gt $script:HivePendingTtlMinutes) {
        Clear-HivePendingChallenge -Path $Path
        return $null
    }
    Return $pending
}

function Set-HivePendingChallenge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Pending    # Username/Session/PoolId/ClientId/CodeDeliveryDestination
    )
    $Pending['ParkedAtUtc'] = ([datetime]::UtcNow).ToString('o')
    $file = Read-HiveCacheFile -Path $Path
    $deviceRaw = if ($file -and $file['device']) { Unprotect-HiveSecretString $file['device'] } else { $null }
    $device = if ($deviceRaw) { ConvertFrom-Json $deviceRaw -AsHashtable } else { $null }
    Write-HiveCacheFile -Path $Path -Device $device -Pending $Pending
}

function Clear-HivePendingChallenge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file = Read-HiveCacheFile -Path $Path
    If (-not $file -or -not $file['pending']) { return }
    $deviceRaw = if ($file['device']) { Unprotect-HiveSecretString $file['device'] } else { $null }
    $device = if ($deviceRaw) { ConvertFrom-Json $deviceRaw -AsHashtable } else { $null }
    Write-HiveCacheFile -Path $Path -Device $device -Pending $null
}

function Clear-HiveCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    If (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
}

function Get-HiveCachedTokenUsable {
    # True when the cached IdToken should still be accepted (skew applied).
    [CmdletBinding()]
    param([Parameter()][hashtable]$Device)
    If (-not $Device -or -not $Device['IdToken'] -or -not $Device['TokenExpiresAtUtc']) { return $false }
    $expires = [datetime]::SpecifyKind([datetime]$Device['TokenExpiresAtUtc'], 'Utc')
    Return ([datetime]::UtcNow -lt $expires.AddSeconds(-$script:HiveTokenSkewSeconds))
}
