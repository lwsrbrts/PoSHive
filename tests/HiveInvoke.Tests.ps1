# Invoke-HiveApiRequest (private/HiveInvoke.ps1): auth header shape, 401
# refresh-and-replay exactly once, rate-limit never retried, host fallback.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PoSHive.psd1') -Force

    # Single mutable state bag captured by the mock's closure.
    $script:State = @{ Calls = @(); Reply = 'ok' }

    $State = $script:State
    $body = {
        param($Uri, $Method, $Headers, $Body, $TimeoutSec, $SkipHttpErrorCheck)
        $State.Calls += @{ Uri = $Uri; Auth = $Headers['Authorization'] }
        switch ($State.Reply) {
            'ok'     { return [pscustomobject]@{ StatusCode = 200; Content = '{"value":42}' } }
            'unauth' {
                # 401 on the first attempt against a URI, 200 afterwards
                if (@($State.Calls.Where({ $_.Uri -eq $Uri })).Count -eq 1) {
                    return [pscustomobject]@{ StatusCode = 401; Content = '{"message":"unauthorized"}' }
                }
                return [pscustomobject]@{ StatusCode = 200; Content = '{"value":43}' }
            }
            'always-unauth' { return [pscustomobject]@{ StatusCode = 401; Content = '{"message":"unauthorized"}' } }
            'ratelimited'   { return [pscustomobject]@{ StatusCode = 403; Content = '{"__type":"ForbiddenException"}' } }
            'notfound'      { return [pscustomobject]@{ StatusCode = 404; Content = '' } }
        }
        throw "unexpected reply: $($State.Reply)"
    }
    Mock -ModuleName PoSHive Invoke-WebRequest ($body.GetNewClosure())
}

Describe 'Invoke-HiveApiRequest' {
    BeforeEach {
        $script:State.Calls = @()
        $script:State.Reply = 'ok'
    }

    It 'sends the raw IdToken with no Bearer prefix' {
        $auth = @{ IdToken = 'RAW-TOKEN' }
        $r = & (Get-Module PoSHive) { param($a) Invoke-HiveApiRequest -Auth $a -Method Get -Uri '/global/devices' } $auth
        $r.value | Should -Be 42
        $script:State.Calls[0].Auth | Should -Be 'RAW-TOKEN'
        $script:State.Calls[0].Uri | Should -Be 'https://beekeeper.hivehome.com/1.0/global/devices'
    }

    It 'refreshes once and replays the request after a 401' {
        $script:State.Reply = 'unauth'
        $auth = @{ IdToken = 'OLD' }
        $auth['Refresh'] = { $auth['IdToken'] = 'NEW' }.GetNewClosure()
        $r = & (Get-Module PoSHive) { param($a) Invoke-HiveApiRequest -Auth $a -Method Get -Uri '/x' } $auth
        $r.value | Should -Be 43
        # first attempt used the stale token, the replay the refreshed one
        $script:State.Calls[0].Auth | Should -Be 'OLD'
        $script:State.Calls[-1].Auth | Should -Be 'NEW'
    }

    It 'throws HiveAuthExpired when the refreshed token is still rejected' {
        $script:State.Reply = 'always-unauth'
        $auth = @{ IdToken = 'OLD' }
        $auth['Refresh'] = { $auth['IdToken'] = 'NEW' }.GetNewClosure()
        { & (Get-Module PoSHive) { param($a) Invoke-HiveApiRequest -Auth $a -Method Get -Uri '/x' } $auth } |
            Should -Throw -ExpectedMessage 'HiveAuthExpired*'
        # refresh is attempted exactly once - no retry loops
        (@($script:State.Calls | Where-Object { $_.Auth -eq 'NEW' })).Count | Should -Be 1
    }

    It 'never retries a 403 rate-limit response' {
        $script:State.Reply = 'ratelimited'
        $auth = @{ IdToken = 'T'; Refresh = { throw 'must not refresh' } }
        { & (Get-Module PoSHive) { param($a) Invoke-HiveApiRequest -Auth $a -Method Get -Uri '/x' } $auth } |
            Should -Throw -ExpectedMessage 'HiveApiRateLimited*'
        $script:State.Calls.Count | Should -Be 1
    }

    It 'falls back to the second host on 404 then reports failure' {
        $script:State.Reply = 'notfound'
        $auth = @{ IdToken = 'T' }
        { & (Get-Module PoSHive) { param($a) Invoke-HiveApiRequest -Auth $a -Method Get -Uri '/x' } $auth } |
            Should -Throw -ExpectedMessage 'HiveApiError*'
        $script:State.Calls.Count | Should -Be 2
        $script:State.Calls[0].Uri | Should -BeLike 'https://beekeeper.hivehome.com/*'
        $script:State.Calls[1].Uri | Should -BeLike 'https://beekeeper-uk.hivehome.com/*'
    }
}
