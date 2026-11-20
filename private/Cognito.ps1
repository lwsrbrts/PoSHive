# Thin AWS Cognito (cognito-idp) JSON-1.1 client for PoSHive.
# InitiateAuth / RespondToAuthChallenge / ConfirmDevice etc. are public
# operations (no SigV4) - see AWS "Authorization models" for Cognito.
# Error bodies carry __type like
# com.amazonaws.cognito.identity.model...#NotAuthorizedException.

$script:HiveCognitoTransientErrors = @(
    'InternalError', 'ServiceUnavailable', 'ThrottlingException',
    'TooManyRequestsException', 'RequestTimeout', 'PriorRequestNotComplete'
)

function Convert-HiveResponseBodyText {
    # PS7 Invoke-WebRequest returns .Content as byte[] for content types it
    # does not treat as text - Cognito's application/x-amz-json-1.1 is one of
    # those, so decoding to UTF-8 here is required, not cosmetic. Any
    # enumerable of bytes (e.g. object[] after pipeline unwrapping) is
    # accepted for robustness.
    [CmdletBinding()]
    param($Content)
    If ($null -eq $Content) { Return '' }
    If ($Content -is [string]) { Return $Content }
    If ($Content -is [byte[]]) { Return [System.Text.Encoding]::UTF8.GetString($Content) }
    If ($Content -is [System.Collections.IEnumerable]) {
        $arr = @($Content)
        If ($arr.Count -gt 0 -and $arr[0] -is [byte]) { Return [System.Text.Encoding]::UTF8.GetString([byte[]]$arr) }
    }
    Return [string]$Content
}

function Invoke-HiveCognitoOperation {
    <#
        POSTs one Cognito operation and returns the parsed response.
        On AWS service errors throws a InvalidOperationException whose message
        starts with the model error code (e.g. 'NotAuthorizedException: ...').
        Transient service errors are retried once after a short delay;
        auth failures (NotAuthorizedException etc.) are never retried.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Operation,     # e.g. InitiateAuth
        [Parameter()][hashtable]$Body = @{},
        [int]$TimeoutSec = 15
    )
    $uri = "https://cognito-idp.$Region.amazonaws.com/"
    $headers = @{
        'Content-Type' = 'application/x-amz-json-1.1'
        'X-Amz-Target' = "AWSCognitoIdentityProviderService.$Operation"
        'User-Agent'   = 'aws-cli/2.13.0 PoSHive'
    }
    $json = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    If (-not $json) { $json = '{}' }

    $attempt = 0
    While ($true) {
        $attempt++
        $response = $null
        $networkError = $null
        Try {
            $response = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -Body $json -TimeoutSec $TimeoutSec -SkipHttpErrorCheck -ErrorAction Stop
        }
        Catch {
            $networkError = $_
        }

        If ($networkError) {
            If ($attempt -lt 2) { Start-Sleep -Seconds 2; Continue }
            throw "CognitoNetworkError: could not reach $uri - $($networkError.Exception.Message)"
        }

        $text = Convert-HiveResponseBodyText $response.Content
        $parsed = $null
        If ($text) {
            Try { $parsed = ConvertFrom-Json $text } Catch { $parsed = $null }
        }

        If ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            If ($null -eq $parsed) {
                $snippet = $text.Substring(0, [Math]::Min(200, $text.Length))
                throw "HiveCognitoBadJson: $Operation returned HTTP $($response.StatusCode) with an unparseable body. $snippet"
            }
            Return , $parsed
        }

        $errorType = 'Unknown'
        $errorMessage = ''
        If ($parsed) {
            If ($parsed.__type) { $errorType = ($parsed.__type -split '#')[-1] }
            ElseIf ($parsed.code) { $errorType = $parsed.code }
            If ($parsed.message) { $errorMessage = $parsed.message }
            ElseIf ($parsed.Message) { $errorMessage = $parsed.Message }
        }
        Else {
            $snippet = $text.Substring(0, [Math]::Min(200, $text.Length))
            throw "HiveCognitoHttpError: $Operation returned HTTP $($response.StatusCode) with an unparseable body. $snippet"
        }

        If ($errorType -in $script:HiveCognitoTransientErrors -and $attempt -lt 2) {
            Start-Sleep -Seconds 2
            Continue
        }
        throw "$errorType`: $errorMessage"
    }
}

function Start-HiveCognitoAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$AuthFlow,
        [Parameter(Mandatory)][hashtable]$AuthParameters
    )
    Return Invoke-HiveCognitoOperation -Region $Region -Operation 'InitiateAuth' -Body @{
        AuthFlow       = $AuthFlow
        ClientId       = $ClientId
        AuthParameters = $AuthParameters
    }
}

function Complete-HiveCognitoChallenge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ChallengeName,
        [Parameter(Mandatory)][hashtable]$ChallengeResponses,
        [string]$Session
    )
    $body = @{
        ClientId           = $ClientId
        ChallengeName      = $ChallengeName
        ChallengeResponses = $ChallengeResponses
    }
    If ($Session) { $body['Session'] = $Session }
    Return Invoke-HiveCognitoOperation -Region $Region -Operation 'RespondToAuthChallenge' -Body $body
}

function Set-HiveCognitoDeviceConfirmed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$DeviceKey,
        [Parameter(Mandatory)][string]$DeviceName,
        [Parameter(Mandatory)][string]$PasswordVerifierB64,
        [Parameter(Mandatory)][string]$SaltB64
    )
    Return Invoke-HiveCognitoOperation -Region $Region -Operation 'ConfirmDevice' -Body @{
        AccessToken                 = $AccessToken
        DeviceKey                   = $DeviceKey
        DeviceName                  = $DeviceName
        DeviceSecretVerifierConfig  = @{
            PasswordVerifier = $PasswordVerifierB64
            Salt             = $SaltB64
        }
    }
}

function Update-HiveCognitoDeviceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$DeviceKey,
        [ValidateSet('remembered', 'not_remembered')][string]$Status = 'remembered'
    )
    Return Invoke-HiveCognitoOperation -Region $Region -Operation 'UpdateDeviceStatus' -Body @{
        AccessToken             = $AccessToken
        DeviceKey               = $DeviceKey
        DeviceRememberedStatus  = $Status
    }
}

function Forget-HiveCognitoDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$DeviceKey
    )
    Return Invoke-HiveCognitoOperation -Region $Region -Operation 'ForgetDevice' -Body @{
        AccessToken = $AccessToken
        DeviceKey   = $DeviceKey
    }
}
