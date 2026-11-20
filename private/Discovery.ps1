# Discover the Hive SSO Cognito pool + public app client by reading the
# login SPA at https://sso.hivehome.com/. Values are embedded as
#   window.HiveSSOPoolId = "eu-west-1_xxx";
#   window.HiveSSOPublicCognitoClientId = "xxx";
# (pyhive performs the same scrape). Hardcoded fallbacks are used when the
# page layout or quoting changes so the module still works offline-ish.

$script:HiveSsoUrl = 'https://sso.hivehome.com/'
$script:HivePoolIdFallback = 'eu-west-1_SamNfoWtf'
$script:HiveClientIdFallback = '3rl4i0ajrmtdm8sbre54p9dvd9'

function Get-HiveCognitoEndpoints {
    <#
        Returns @{ PoolId; ClientId; Source } where Source is 'scrape' or
        'fallback'. Never throws for a scrape failure - just falls back.
    #>
    [CmdletBinding()]
    param([int]$TimeoutSec = 15)
    $result = @{ PoolId = $script:HivePoolIdFallback; ClientId = $script:HiveClientIdFallback; Source = 'fallback' }
    Try {
        # Browser UA: some CDNs serve different content to unusual clients.
        $page = Invoke-WebRequest -Uri $script:HiveSsoUrl -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -TimeoutSec $TimeoutSec -SkipHttpErrorCheck -ErrorAction Stop
        $content = Convert-HiveResponseBodyText $page.Content
        $m = [regex]::Matches($content, 'window\.(\w+)\s*=\s*(["''])(.*?)\2')
        $vars = @{}
        ForEach ($g In $m) { $vars[$g.Groups[1].Value] = $g.Groups[3].Value }
        If ($vars['HiveSSOPoolId']) { $result['PoolId'] = $vars['HiveSSOPoolId']; $result['Source'] = 'scrape' }
        If ($vars['HiveSSOPublicCognitoClientId']) { $result['ClientId'] = $vars['HiveSSOPublicCognitoClientId']; $result['Source'] = 'scrape' }
    }
    Catch {
        Write-Verbose "PoSHive: could not scrape $($script:HiveSsoUrl) for Cognito config ($($_.Exception.Message)); using embedded fallback values."
    }
    # Sanity: a pool id looks like 'region_GUID'.
    If ($result['PoolId'] -notmatch '^[a-z0-9-]+_[A-Za-z0-9]+$' -or -not $result['ClientId']) {
        $result['PoolId'] = $script:HivePoolIdFallback
        $result['ClientId'] = $script:HiveClientIdFallback
        $result['Source'] = 'fallback'
    }
    Return $result
}

function Get-HiveRegionFromPoolId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PoolId)
    If ($PoolId -match '^([a-z0-9-]+)_[A-Za-z0-9]+$') { Return $Matches[1] }
    Return 'eu-west-1'
}
