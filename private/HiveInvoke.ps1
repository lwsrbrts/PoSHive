# Hive data-API (beekeeper) request helper used by class Hive.
# - Authorization header carries the RAW IdToken (no 'Bearer ' prefix).
# - Host fallback: beekeeper.hivehome.com -> beekeeper-uk.hivehome.com on
#   gateway-level 403/404 (behaviour reported by Homebridge-Hive-Thermostat).
# - HTTP 401: refresh once via the supplied callback and replay; a
#   ForbiddenException-style 403 (rate limiting) is NEVER retried.

$script:HiveApiBase = 'https://beekeeper.hivehome.com/1.0'
$script:HiveApiBaseFallback = 'https://beekeeper-uk.hivehome.com/1.0'
$script:HiveApiUserAgent = 'Hive/12.04.0 iOS/18.3.1 Apple'

function Invoke-HiveApiRequest {
    <#
        Executes one authenticated Hive data-API call.
        $Auth: hashtable with 'IdToken' and (optionally) a 'Refresh'
        scriptblock that refreshes the Auth hashtable in place (Connect-Hive
        provides this from the class). Returns parsed JSON or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Auth,
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,          # '/devices' or absolute https URI
        $Body,                                       # string (already JSON) or psobject
        [int]$TimeoutSec = 30
    )
    $isAbsolute = $Uri -match '^https://'
    $hosts = @($script:HiveApiBase, $script:HiveApiBaseFallback)
    $lastError = $null
    $refreshed = $false

    foreach ($apiBase in $hosts) {
        $requestUri = if ($isAbsolute) { $Uri } else { "$apiBase$Uri" }
        $loop = $true
        $nextHost = $false
        while ($loop) {
            $headers = @{
                'Authorization' = $Auth['IdToken']     # raw token, no Bearer
                'User-Agent'    = $script:HiveApiUserAgent
                'Accept'        = 'application/json'
                'Content-Type'  = 'application/json'
            }
            $params = @{ Method = $Method; Uri = $requestUri; Headers = $headers; TimeoutSec = $TimeoutSec; SkipHttpErrorCheck = $true }
            if ($null -ne $Body) {
                $params['Body'] = if ($Body -is [string]) { $Body } else { ConvertTo-Json $Body -Depth 99 -Compress }
            }
            $response = Invoke-WebRequest @params
            $status = [int]$response.StatusCode
            $content = Convert-HiveResponseBodyText $response.Content

            if ($status -ge 200 -and $status -lt 300) {
                $loop = $false
                if (-not $content) { return $null }
                Try { return ConvertFrom-Json $content }
                Catch { throw "HiveApiBadJson: $requestUri returned non-JSON content (HTTP $status)." }
            }
            elseif ($status -eq 401) {
                if (-not $refreshed -and $Auth['Refresh']) {
                    $refreshed = $true
                    Try { & $Auth['Refresh'] } Catch {
                        throw "HiveAuthExpired: token refresh failed during API call ($($_.Exception.Message)). Run Connect-Hive again."
                    }
                    # loop again with the fresh IdToken
                } else {
                    $loop = $false
                    $snippet = $content.Substring(0, [Math]::Min(200, $content.Length))
                    throw "HiveAuthExpired: Hive API rejected the token (HTTP 401). Run Connect-Hive again. $snippet"
                }
            }
            elseif ($status -eq 403 -and ($content -like '*Forbidden*' -or $content -like '*Throttl*')) {
                # Rate limiting (empirically ~25-request bursts cause a
                # 1-2 minute lockout). Never retry; surface to caller.
                $loop = $false
                throw 'HiveApiRateLimited: Hive API returned 403 (likely rate limiting). Wait 1-2 minutes before retrying; do not loop.'
            }
            elseif ($status -eq 403 -or $status -eq 404) {
                $lastError = "HTTP $status on $requestUri"
                $loop = $false
                $nextHost = $true
            }
            else {
                $loop = $false
                $snippet = $content.Substring(0, [Math]::Min(300, $content.Length))
                throw "HiveApiError: HTTP $status on $Method $requestUri. $snippet"
            }
        }
        if (-not $nextHost) { return }   # succeeded or threw inside loop
    }
    throw "HiveApiError: $Method $Uri failed on both API hosts. Last: $lastError"
}
