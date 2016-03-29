# PoSHive
A PowerShell class (yes, again) for exerting a little control over your British Gas Hive system.

The idea is to be able to use PowerShell scripting to exert more powerful logic control over the state of your heating system.

If it's Summer, turn the heating off completely.
If it's Autumn, turn the schedule on.

If the temperature outside is less than 10 degrees, the inside temperature is less than 12 degrees and the heating is Off, turn it on for an hour.

Monitor tweets from an account and set the temperature based on the tweet.

##Import the class in to PowerShell using Import-Module
```powershell
Import-Module D:\PoSHive\PoSHive.ps1
```

## Instantiate the class and assign to an object
```powershell
$h = [Hive]::new('user@domain.com', 'myhivewebsitepassword')
```
## Log in to the Hive site
```powershell
$h.Login()
```

## Get details about the climate in your house
```powershell
$h.GetClimate()
```

## Get the current temperature - not very accurate, Thermostat device is better.
```powershell
$h.GetTemperature()
```

## Set the temperature (automatically sets heating mode to MANUAL)
```powershell
$h.SetTemperature(21)
```

## NOT WORKING YET
## Change the heating mode to one of Enum [HeatingMode]
```powershell
$h.SetHeatingMode('OFF')
```

## Be nice and log out/destroying ApiSession and associated cookie.
```powershell
$h.Logout()
```
