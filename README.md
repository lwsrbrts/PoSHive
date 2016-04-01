# PoSHive
A PowerShell class (yes, again) for exerting a little control over your British Gas Hive system.

## This code is not sanctioned by or affiliated with British Gas in any way. 

The idea is to be able to use PowerShell scripting to exert more powerful logic control over the state of your heating system.
In its basic form, it allows you to get information about the system (to perform additional actions) and set the heating mode of the system as well as the temperature.

The class does not currently support multi-zone/thermostat Hive installations (I don't have a multi-zone Hive system, sorry) - if you can help, feel free to branch and submit a pull request when you're happy to.

Some examples of use (and the reasons why I did this)
* If it's Summer, turn the heating off completely.
* If it's Autumn, turn the schedule on.
* Automatically tweet the current temperature to you at 5pm. (Tweeting isn't implemented in this class, that's up to you!)
* If the temperature outside is less than 10 degrees, the inside temperature is less than 12 degrees and the heating is Off, turn it on for an hour.
* Monitor tweets from a specific account (yours) and so long as they're valid, set the temperature based on the tweet.
* Set your Philips Hue Light colour based on the current temperature in the home - why not use my PoSHue PowerShell class? ;)
* Have as many "on and off times" as you like - you're not limited by anything.

Obviously these are example uses, this class simply provides the ability to control your heating system by abstracting the British Gas Hive APIv6.1 in to PowerShell classes/methods.

##Import the class in to PowerShell session
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

## Get the current temperature from Thermostat (formatted with symbols)
```powershell
$h.GetTemperature($true)
```
## Get the current temperature from Thermostat (unformatted)
```powershell
$h.GetTemperature($false)
```

## Set the temperature - only works if heating is not OFF.
```powershell
$h.SetTemperature(21)
```

## Change the heating mode to one of Enum [HeatingMode]
```powershell
$h.SetHeatingMode('OFF')
$h.SetHeatingMode('MANUAL')
$h.SetHeatingMode('SCHEDULE')
```

## Be nice and log out.
```powershell
$h.Logout()
```
