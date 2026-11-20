# PoSHive v3 sample session.
#
# Authentication now uses AWS Cognito SRP + SMS one-time codes (the Hive
# login flow introduced in 2020). The first sign-in on a machine sends an
# SMS code; PoSHive then registers and "remembers" this device, so later
# sign-ins reuse the encrypted local cache (~\.poshive\hive-device.json)
# and no SMS is sent.
#
# Never hard-code credentials in scripts. Pick one:
#   1. Run the sample, get prompted for credentials (Get-Credential).
#   2. Dot-source your own untracked secrets file that sets $Cred.

using module ./PoSHive.psd1

# --- Option 2 example: load your own secrets (keep this file untracked) ---
# . "$HOME\poshive-secrets.ps1"   # must define $Cred as a [pscredential]

if (-not $Cred) {
    $Cred = Get-Credential -Message 'Hive account (email + password)'
}

# --- Sign in ---------------------------------------------------------------
# Interactive: on a brand-new device you will be prompted for the SMS code.
Connect-Hive -Credential $Cred

# Non-interactive pipelines: park instead of prompting, then finish with
# Complete-HiveLogin once the code arrives.
#   $r = Connect-Hive -Credential $Cred -NoPrompt
#   if ($r.Status -eq 'WaitingForSmsCode') { Complete-HiveLogin -Code (Read-Host 'SMS code') }

# --- Inspect auth state ----------------------------------------------------
Get-HiveAuthState

# --- Use the data-plane class ----------------------------------------------
# The class picks up the tokens from the cache; Login() refreshes as needed.
$Hive = [Hive]::new()
$Hive.Login()

$Hive.GetHeatingState('Downstairs')
$Hive.GetHotWaterState('Downstairs')
$Hive.GetTemperature()
$Hive.GetWeather()

# Hot water boost examples
$Hive.SetHotWaterBoostMode('HALF')
$Hive.CancelHotWaterBoostMode()

# --- Sign out (local only; the remembered device stays registered) ---------
$Hive.Logout()
# To also forget the device server-side:
#   Disconnect-Hive -ForgetDevice
