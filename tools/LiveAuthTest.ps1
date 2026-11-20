<#
    .SYNOPSIS
    Owner-run live validation of the PoSHive v3 auth engine against the real
    Hive (British Gas) Cognito environment.

    .DESCRIPTION
    Run this yourself - it prompts for your password interactively and never
    writes credentials or tokens to disk beyond the normal encrypted PoSHive
    cache (~\.poshive\hive-device.json), and never prints tokens.

    It walks the full story in order:

      1. Connect-Hive fresh login  -> expect an SMS OTP (first time on a box)
      2. Enter the SMS code        -> expect success + device registration
      3. Get-HiveAuthState         -> expect device/refresh to be available
      4. Connect-Hive again        -> expect NO SMS (cached tokens path)
      5. Force expiry + Connect-Hive -> expect silent refresh, still NO SMS
      6. Optional: -ForgetDevice and repeat step 1 to re-test registration

    Usage:
      pwsh -File tools\LiveAuthTest.ps1              # interactive
      pwsh -File tools\LiveAuthTest.ps1 -FullReset   # forget device first

    Failures print the Cognito error code; the most useful outcomes to report
    back are the PASS/FAIL lines and any error codes.
#>
[CmdletBinding()]
param(
    [switch]$FullReset
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'PoSHive.psd1') -Force

function Step([string]$name)   { Write-Host "`n== $name ==" -ForegroundColor Cyan }
function Pass([string]$msg)    { Write-Host "PASS  $msg" -ForegroundColor Green }
function Fail([string]$msg)    { Write-Host "FAIL  $msg" -ForegroundColor Red }

$cwd = $PWD

# ---------------------------------------------------------------- optional reset
if ($FullReset) {
    Step 'FullReset: forgetting the remembered device'
    try {
        $null = Disconnect-Hive -ForgetDevice -ErrorAction Stop
        Pass 'device forgotten and local cache cleared'
    } catch {
        Fail "Disconnect-Hive -ForgetDevice: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------------ fresh login
Step 'Step 1: fresh login (expect an SMS code to be sent)'
$cred = Get-Credential -Message 'Hive account (email + password)'
try {
    $r = Connect-Hive -Credential $cred -Force
    if ($r.Status -eq 'Connected') {
        Pass "connected via '$($r.Path)' (no OTP was required - fine)"
    }
} catch {
    Fail "Connect-Hive: $($_.Exception.Message)"
    exit 1
}

# ------------------------------------------------------- interactive OTP entry
if ($r.Status -eq 'WaitingForSmsCode') {
    Step 'Step 2: enter the SMS code'
    $code = Read-Host -Prompt "SMS code sent to $($r.CodeDeliveryDestination)"
    try {
        $r2 = Connect-Hive -Credential $cred -Otp $code
        if ($r2.Status -eq 'Connected') { Pass 'SMS login completed and device registered' }
        else { Fail "unexpected status: $($r2.Status)" }
    } catch {
        Fail "OTP completion: $($_.Exception.Message)"
        exit 1
    }
}

# ------------------------------------------------------------------ state check
Step 'Step 3: Get-HiveAuthState (expect DeviceRegistered/RefreshToken True)'
$st = Get-HiveAuthState
$st | Format-List | Out-String | Write-Host
if ($st.DeviceRegistered)   { Pass 'device registered' }        else { Fail 'device NOT registered (ConfirmDevice may have been rejected)' }
if ($st.RefreshTokenPresent){ Pass 'refresh token cached' }     else { Fail 'no refresh token cached' }

# ------------------------------------------------------------ no-SMS reconnect
Step 'Step 4: reconnect (expect NO SMS - cached tokens)'
try {
    $r = Connect-Hive -Credential $cred
    if ($r.Status -eq 'Connected' -and $r.Path -eq 'cached') { Pass 'cached tokens reused, no SMS' }
    elseif ($r.Status -eq 'Connected') { Pass "connected via '$($r.Path)' (not 'cached', but no SMS needed)" }
    else { Fail "expected cached login, got status $($r.Status) - an SMS was sent" }
} catch {
    Fail "cached reconnect: $($_.Exception.Message)"
}

# ------------------------------------------------------------ silent refresh
Step 'Step 5: force token expiry and reconnect (expect silent refresh, NO SMS)'
$cachePath = & (Get-Module PoSHive) { Get-HiveCachePath }
$dev = & (Get-Module PoSHive) { param($p) Get-HiveCachedDevice -Path $p } $cachePath
if ($dev) {
    $dev['TokenExpiresAtUtc'] = ([datetime]::UtcNow.AddMinutes(-1)).ToString('o')
    & (Get-Module PoSHive) { param($p, $d) Set-HiveCachedDevice -Path $p -Device $d } $cachePath, $dev
    try {
        $r = Connect-Hive -Credential $cred
        if ($r.Status -eq 'Connected' -and $r.Path -eq 'refresh') { Pass 'silent refresh worked, no SMS' }
        elseif ($r.Status -eq 'Connected') { Pass "connected via '$($r.Path)'" }
        else { Fail "expected refresh, got status $($r.Status) - an SMS was sent" }
    } catch {
        Fail "refresh reconnect: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------------- data plane
Step 'Step 6: data-plane smoke test (user profile + devices)'
try {
    $user = & (Get-Module PoSHive) {
        param($p)
        $d = Get-HiveCachedDevice -Path $p
        if (-not $d) { throw 'no cached session' }
        $auth = @{ IdToken = $d['IdToken']; AccessToken = $d['AccessToken']; RefreshToken = $d['RefreshToken'] }
        Invoke-HiveApiRequest -Auth $auth -Method Get -Uri '/nodes/all?products=true&devices=true&actions=true'
    } $cachePath
    Pass "profile loaded (user id: $($user.id))"
    $devices = & (Get-Module PoSHive) {
        param($p)
        $d = Get-HiveCachedDevice -Path $p
        $auth = @{ IdToken = $d['IdToken']; AccessToken = $d['AccessToken']; RefreshToken = $d['RefreshToken'] }
        Invoke-HiveApiRequest -Auth $auth -Method Get -Uri '/global/devices?after='
    } $cachePath
    Pass "devices endpoint responded ($(@($devices).Count) records)"
} catch {
    Fail "data plane: $($_.Exception.Message)"
    Write-Host '     (beekeeper host/endpoint drift is a known unknown - report the error code)'
}

Write-Host "`nDone. Report the PASS/FAIL lines above (no secrets in them)." -ForegroundColor Cyan
Set-Location $cwd
