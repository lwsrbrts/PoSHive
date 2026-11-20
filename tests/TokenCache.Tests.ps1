# DPAPI token-cache behaviour: round-trip, secrecy-at-rest, TTLs, corruption.
# Dot-sources the private files directly (no network, no module mocks needed).

BeforeAll {
    $root = Join-Path $PSScriptRoot '..'
    . (Join-Path $root 'private' 'TokenCache.ps1')
    . (Join-Path $root 'private' 'Discovery.ps1')
    $script:Cache = Join-Path ([IO.Path]::GetTempPath()) ('poshive-cache-' + [guid]::NewGuid().ToString('n') + '.json')
    $script:Now = [datetime]::UtcNow
}

AfterAll {
    Remove-Item $script:Cache -Force -ErrorAction SilentlyContinue
}

Describe 'Get-HiveCachePath' {
    It 'defaults to a .poshive hive-device.json path' {
        (Get-HiveCachePath) | Should -BeLike '*hive-device.json'
    }
    It 'honours an explicit -Path' {
        (Get-HiveCachePath -Path $script:Cache) | Should -Be $script:Cache
    }
}

Describe 'Device record persistence' {
    BeforeAll {
        $dev = @{
            Username = 'me@example.com'; DeviceKey = 'dk'; DeviceGroupKey = 'gk'
            DevicePassword = 'secret-pw'; RefreshToken = 'rt'; IdToken = 'id'; AccessToken = 'at'
            TokenExpiresAtUtc = $script:Now.AddHours(1).ToString('o')
            PoolId = 'eu-west-1_x'; ClientId = 'cid'
        }
        Set-HiveCachedDevice -Path $script:Cache -Device $dev
    }

    It 'round-trips the decrypted device record' {
        $loaded = Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com'
        $loaded.DevicePassword | Should -Be 'secret-pw'
        $loaded.RefreshToken   | Should -Be 'rt'
        $loaded.DeviceKey      | Should -Be 'dk'
    }

    It 'hides the record when the username does not match' {
        (Get-HiveCachedDevice -Path $script:Cache -Username 'other@example.com') | Should -BeNullOrEmpty
    }

    It 'never writes the device secret to disk in plaintext' {
        Get-Content $script:Cache -Raw | Should -Not -BeLike '*secret-pw*'
    }

    It 'considers a future expiry usable' {
        $loaded = Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com'
        (Get-HiveCachedTokenUsable -Device $loaded) | Should -BeTrue
    }

    It 'considers a recently-expired token unusable (skew)' {
        $loaded = Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com'
        $loaded.TokenExpiresAtUtc = $script:Now.AddMinutes(-5).ToString('o')
        (Get-HiveCachedTokenUsable -Device $loaded) | Should -BeFalse
    }

    It 'Clear-HiveCache removes the file' {
        Clear-HiveCache -Path $script:Cache
        Test-Path $script:Cache | Should -BeFalse
    }
}

Describe 'Pending OTP challenge' {
    BeforeAll {
        $dev = @{ Username='me@example.com'; DeviceKey='dk'; DeviceGroupKey='gk'; DevicePassword='pw'; RefreshToken='rt'; IdToken='id'; AccessToken='at'; TokenExpiresAtUtc=$script:Now.AddHours(1).ToString('o') }
        Set-HiveCachedDevice -Path $script:Cache -Device $dev
        Set-HivePendingChallenge -Path $script:Cache -Pending @{ Username='me@example.com'; Session='sess'; PoolId='p'; ClientId='c'; CodeDeliveryDestination='+447********' }
    }
    AfterAll { Clear-HiveCache -Path $script:Cache }

    It 'round-trips the parked session with a timestamp' {
        $p = Get-HivePendingChallenge -Path $script:Cache
        $p.Session | Should -Be 'sess'
        $p.ParkedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'parking a challenge does not disturb the device record' {
        (Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com').DeviceKey | Should -Be 'dk'
    }

    It 'expires a challenge parked more than the TTL ago' {
        $file = Read-HiveCacheFile -Path $script:Cache
        $pend = ConvertFrom-Json (Unprotect-HiveSecretString $file['pending']) -AsHashtable
        $pend['ParkedAtUtc'] = $script:Now.AddMinutes(-30).ToString('o')
        $dev = Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com'
        Write-HiveCacheFile -Path $script:Cache -Device $dev -Pending $pend
        (Get-HivePendingChallenge -Path $script:Cache) | Should -BeNullOrEmpty
        (Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com').DeviceKey | Should -Be 'dk'
    }

    It 'Clear-HivePendingChallenge leaves the device intact' {
        Set-HivePendingChallenge -Path $script:Cache -Pending @{ Username='u'; Session='s' }
        Clear-HivePendingChallenge -Path $script:Cache
        (Get-HivePendingChallenge -Path $script:Cache) | Should -BeNullOrEmpty
        (Get-HiveCachedDevice -Path $script:Cache -Username 'me@example.com').DeviceKey | Should -Be 'dk'
    }
}

Describe 'Corrupt cache tolerance' {
    It 'returns no device for an unreadable cache file' {
        Set-Content -Path $script:Cache -Value '{not json'
        Get-HiveCachedDevice -Path $script:Cache | Should -BeNullOrEmpty
    }
}

Describe 'Endpoint discovery helpers' {
    It 'parses the region out of a pool id' {
        Get-HiveRegionFromPoolId 'eu-west-1_SamNfoWtf' | Should -Be 'eu-west-1'
    }
    It 'falls back to eu-west-1 for an unrecognised pool id' {
        Get-HiveRegionFromPoolId 'garbage' | Should -Be 'eu-west-1'
    }
}
