# PoSHive 0.1 - Alpha
A PowerShell 5 class to control your British Gas Hive system.

> **This project is not sanctioned by or affiliated with British Gas in any way.**


## Purpose

The purpose of this class is to enable you to use PowerShell (v5) scripting to exert more powerful logic control over the state of your heating system.
In its basic form, it allows you to set the heating mode of the system and the temperature, including the Boost option. Additionally, it allows you to more easily expose information about the system and its settings to enable you to perform powerful logic operations. If you find a bug or have a feature request, please open a new Issue and let me know so I can resolve it.

## Multi-zone systems
The class **does not currently support multi-zone/thermostat Hive installations** (I don't have a multi-zone Hive system, sorry). Most of the setting methods will only retrieve the first thermostat identified in the system, in some cases, this might not even be the primary one you want to control if you have a multi-thermostat system - if you can help, feel free to branch and submit a pull request when you're happy to or you could send me the JSON response from a Get to /omnia/nodes and I'll see how to determine the correct thermostat.

## Examples
Some examples of use (and the reasons why I did this)
* Ask a weather service if it's Summer, turn the heating off completely.
* If it's Autumn, turn the schedule on.
* Automatically tweet the current temperature to you at 5pm. (Tweeting isn't implemented in this class, that's up to you!)
* If the temperature outside is less than 10 degrees, the inside temperature is less than 12 degrees and the heating is Off, turn it on for an hour.
* Monitor tweets from a specific account (yours) and so long as they're valid, set the temperature based on the tweet.
* Set your Philips Hue Light colour based on the current temperature in the home - why not use my PoSHue PowerShell class? ;)
* Have as many "on and off times" as you like - you're not limited by anything.

Obviously these are example uses, this class simply provides the ability to control your heating system by abstracting the British Gas Hive APIv6.1 in to PowerShell classes/methods.
## Using the class

### Import the class in to PowerShell session
```powershell
Import-Module D:\PoSHive\PoSHive.ps1
```

### Instantiate the class
Takes two [string] parameters for username and password, in that order.
```powershell
$h = [Hive]::new('user@domain.com', 'myhivewebsitepassword')
```

### Log in to the Hive API
Simply logs in to the Hive API. A session id is assigned by the Hive API that is used for subsequent communications and acts as your authorisation token.
```powershell
$h.Login()
```

### Get details about the nodes (devices)
Doesn't provide much useful information but I leave the method open for use for example so that you can implement your own logic based on the values of attributes. Use $h.Nodes (a call to GetClimate() is made regularly and stored in this class variable).
```powershell
$h.GetClimate()
```

### Get the current temperature from Thermostat (formatted with symbols)
```powershell
$h.GetTemperature($true) # Return 21.1°C
```
### Get the current temperature from Thermostat (unformatted)
```powershell
$h.GetTemperature($false) # Return 21.1
```

### Set the temperature
Only works if heating mode is not currently **OFF**. Yes, I could turn the heating on in order to set the temperature but to what mode? That's up to you so I left this.
```powershell
$h.SetTemperature(21)
```

### Change the heating mode
Takes a parameter of type `[HeatingMode]` `OFF` | `MANUAL` | `SCHEDULE`
```powershell
$h.SetHeatingMode('OFF')
$h.SetHeatingMode('MANUAL')
$h.SetHeatingMode('SCHEDULE')
```

### Boost the heating system for the defined time.
Always boosts to 22°C - this is the same as the Hive site default boost temperature.
Takes a parameter of type `[BoostTime]` `HALF` | `ONE` | `TWO` | `THREE` | `FOUR` | `FIVE` | `SIX` which is based on hours and converted to minutes before being submitted to the API. I haven't used an `[int]` type because the API does mention these values specifically so it's best to enforce their use.
```powershell
$h.SetBoostMode('HALF')
$h.SetBoostMode('ONE')
$h.SetBoostMode('TWO')
$h.SetBoostMode('THREE')
$h.SetBoostMode('FOUR')
$h.SetBoostMode('FIVE')
$h.SetBoostMode('SIX')
```

### Log out
The session will automatically expire from the Hive API in approx 20 minutes but if you're performing just a few actions, log out anyway.
```powershell
$h.Logout()
```

## Mentions
An honourable mention goes out to https://github.com/aklambeth for the inspiration and advising to implement using the v6 API.

## Questions?
If you have questions, comments, enhancement ideas etc. [post an issue.](https://github.com/lwsrbrts/PoSHive/issues)