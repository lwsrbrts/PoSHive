# Invoke-HiveCognitoOperation response handling. Regression guard: PS7
# Invoke-WebRequest returns .Content as byte[] for Cognito's
# application/x-amz-json-1.1, which previously parsed as $null and surfaced
# as an empty challenge / 'Unknown' error (found against the live service).

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PoSHive.psd1') -Force
    $script:State = @{ Reply = 'ok-bytes' }

    $State = $script:State
    $body = {
        param($Uri, $Method, $Headers, $Body, $TimeoutSec, $SkipHttpErrorCheck)
        function Respond([int]$Status, [string]$Json, [switch]$AsBytes) {
            # comma keeps byte[] intact through the function pipeline,
            # matching what real PS7 Invoke-WebRequest exposes
            $content = if ($AsBytes) { , [System.Text.Encoding]::UTF8.GetBytes($Json) } else { $Json }
            return [pscustomobject]@{ StatusCode = $Status; Content = $content }
        }
        switch ($State.Reply) {
            'ok-bytes'    { return Respond 200 '{"ChallengeName":"PASSWORD_VERIFIER","Session":"s1"}' -AsBytes }
            'ok-string'   { return Respond 200 '{"ChallengeName":"PASSWORD_VERIFIER","Session":"s1"}' }
            'err-bytes'   { return Respond 400 '{"__type":"com.amazonaws.cognito.identity.model.AWSCognitoIdentityProviderException#NotAuthorizedException","message":"Incorrect username or password."}' -AsBytes }
            'badjson'     { return Respond 200 'not json at all' -AsBytes }
            'errbadjson'  { return Respond 400 'gateway blew up' -AsBytes }
        }
        throw "unexpected reply: $($State.Reply)"
    }
    Mock -ModuleName PoSHive Invoke-WebRequest ($body.GetNewClosure())
}

Describe 'Invoke-HiveCognitoOperation response decoding' {
    It 'parses a 2xx byte[] body (real PS7 Cognito shape)' {
        $script:State.Reply = 'ok-bytes'
        $r = & (Get-Module PoSHive) {
            Start-HiveCognitoAuth -Region 'eu-west-1' -ClientId 'cid' -AuthFlow 'USER_SRP_AUTH' -AuthParameters @{ USERNAME = 'u'; SRP_A = 'aa' }
        }
        $r.ChallengeName | Should -Be 'PASSWORD_VERIFIER'
        $r.Session | Should -Be 's1'
    }

    It 'parses a 2xx string body too' {
        $script:State.Reply = 'ok-string'
        $r = & (Get-Module PoSHive) {
            Start-HiveCognitoAuth -Region 'eu-west-1' -ClientId 'cid' -AuthFlow 'USER_SRP_AUTH' -AuthParameters @{ USERNAME = 'u'; SRP_A = 'aa' }
        }
        $r.ChallengeName | Should -Be 'PASSWORD_VERIFIER'
    }

    It 'maps a byte[] error body to the model error code' {
        $script:State.Reply = 'err-bytes'
        { & (Get-Module PoSHive) {
            Start-HiveCognitoAuth -Region 'eu-west-1' -ClientId 'cid' -AuthFlow 'USER_SRP_AUTH' -AuthParameters @{ USERNAME = 'u'; SRP_A = 'aa' }
        } } | Should -Throw -ExpectedMessage 'NotAuthorizedException: Incorrect username or password.*'
    }

    It 'throws HiveCognitoBadJson on an unparseable success body' {
        $script:State.Reply = 'badjson'
        { & (Get-Module PoSHive) {
            Start-HiveCognitoAuth -Region 'eu-west-1' -ClientId 'cid' -AuthFlow 'USER_SRP_AUTH' -AuthParameters @{ USERNAME = 'u'; SRP_A = 'aa' }
        } } | Should -Throw -ExpectedMessage 'HiveCognitoBadJson*'
    }

    It 'throws HiveCognitoHttpError on an unparseable error body' {
        $script:State.Reply = 'errbadjson'
        { & (Get-Module PoSHive) {
            Start-HiveCognitoAuth -Region 'eu-west-1' -ClientId 'cid' -AuthFlow 'USER_SRP_AUTH' -AuthParameters @{ USERNAME = 'u'; SRP_A = 'aa' }
        } } | Should -Throw -ExpectedMessage 'HiveCognitoHttpError*'
    }
}
