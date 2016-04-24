# PoSHive
A PowerShell 5 class to control your British Gas Hive (heating) system.

> **This project is not sanctioned by or affiliated with British Gas in any way.**

##Release Notes
 * [**1.2.0 - Scheduler**](https://github.com/lwsrbrts/PoSHive/releases/tag/v1.2.0) - 23/04/2016 - Functions for saving/setting heating schedules to/from a JSON file.
 * **1.1.2 - Color[sic]** - 22/04/2016 - Removed the reliance on System.Drawing.Color assembly being loaded for use in this class. Moved it to PoSHue.
 * **1.1.1 - User** - 22/04/2016 - User profile data (from the Hive site) is now an accessible class property ($h.User). Added methods to get outside weather conditions.
 * **1.1.0 - Holiday** - 14/04/2016 - Added methods to get, set and cancel holiday mode. Fixed a bug preventing error messages returning useful information.
 * **1.0.0 - Release** - 07/04/2016 - first release of the PoSHive class. Allows getting, setting temperature, setting heating mode to auto, manual or off. Turning on or cancelling of Boost mode.

## Purpose

The purpose of this class is to enable you to use PowerShell (v5) scripting to exert more powerful logic control over the state of your heating(!) system.
The class allows you to set most if not all of the same functionality as provided by the Hive website for your heating(!) system; including Heating Mode, Boost, Schedules and Holiday Schedule. Additionally, it allows you to more easily expose information about the system and its settings to enable you to perform powerful logic operations. If you find a bug or have a feature request, please open a new issue or let me know so I can resolve it.

## What can't it do?
### Hot Water
The class **does not currently support Hot Water systems** - I have a combi-boiler with on-demand hot water so I don't have a Hive hot water system and so can't develop for it unfortunately. If you can help, feel free to branch/fork and submit a pull request when you're happy to.<br/> *If you would REALLY like me to develop for these features and you don't have the skills in PowerShell, you can share your login with me and I will develop using that access. I realise that's a big ask of anyone but I'm trustworthy and only interested in improving PoSHive for everyone, not messing up your heating/hot water system.*
### Multi-zone Systems
The class **does not currently support multi-zone/thermostat Hive installations** - I'm not currently blessed with a large enough house to require a multi-zone Hive system so unfortunately, I'm not able to develop for this. Honestly, this is the biggest concern for me in terms of PoSHive being widely adopted as I have to make certain assumptions in the code about the primary thermostat/receiver. As a result, most of the setting methods will only retrieve the **first** thermostat identified in the system, in some cases, this might not even be the primary one you want to control if you have a multi-thermostat system. If you can help, feel free to branch and submit a pull request when you're happy to or you could send me the JSON response from a Get to /omnia/nodes (use `$h.GetClimate() | ConvertTo-Json`) and I'll see if I can determine the correct thermostat from the JSON output. <br/> *If you would REALLY like me to develop for multi-zone and you don't have the skills in PowerShell, you can share your login with me and I will develop using that access. I realise that's a big ask of anyone but I'm trustworthy and only interested in improving PoSHive for everyone, not messing up your heating/hot water system.*

## Examples
Some examples of use (and the reasons why I did this)
* Ask a weather service if it's Summer, turn the heating off completely.
* If it's Autumn, turn the Autumn schedule on (from a saved file)
* Automatically tweet the current temperature to you at 5pm. (Tweeting isn't implemented in this class, that's up to you!)
* If the temperature outside is less than 10 degrees, the inside temperature is less than 12 degrees and the heating is Off, turn it on for an hour at 20°C.
* Monitor tweets from a specific account (yours) and, so long as they're valid, set the temperature based on the tweet.
* Set your Philips Hue Light colour based on the current temperature inside or outside the home - why not use my PoSHue PowerShell class? ;)
* Have as many "on and off times" as you like - using Windows Task Scheduler, you're not limited by anything so primitive as 6 schedules a day! ;)

 ![alt-text](http://www.lewisroberts.com/wp-content/uploads/2016/04/poshivebasics.gif "PoSHive basics")

Obviously these are example uses, this class simply provides the ability to control your heating system by abstracting the British Gas Hive APIv6.1 in to PowerShell classes/methods.
## Using the class

### Import the class in to PowerShell session
```powershell
Import-Module D:\PoSHive\PoSHive.ps1
```

### Instantiate the class
Takes two [string] parameters for username and password, in that order. There are two ways to instantiate.
```powershell
$h = [Hive]::new('user@domain.com', 'myhivewebsitepassword')
# or
$h = New-Object -TypeName Hive -ArgumentList ('user@domain.com', 'myhivewebsitepassword')

```

### Properties and methods
If you want to see all of the available properties and methods in the class, get its members. Some methods may not be documented or hidden :o - use `-Force` to see all methods/properties.
```powershell
$h | Get-Member
<# Returns eg.
   TypeName: Hive

Name                       MemberType Definition
----                       ---------- ----------
CancelBoostMode            Method     string CancelBoostMode()
CancelHolidayMode          Method     string CancelHolidayMode()
Equals                     Method     bool Equals(System.Object obj)
GetClimate                 Method     psobject GetClimate()
GetHashCode                Method     int GetHashCode()
GetHolidayMode             Method     string GetHolidayMode()
GetTemperature             Method     psobject GetTemperature(bool FormattedValue)
GetType                    Method     type GetType()
GetUser                    Method     psobject GetUser()
GetWeather                 Method     psobject GetWeather(), psobject GetWeather(string Postcode)
GetWeatherTemperature      Method     int GetWeatherTemperature()
Login                      Method     void Login()
Logout                     Method     psobject Logout()
SaveHeatingScheduleToFile  Method     void SaveHeatingScheduleToFile(System.IO.DirectoryInfo DirectoryPath)
SetBoostMode               Method     psobject SetBoostMode(BoostTime Duration)
SetHeatingMode             Method     psobject SetHeatingMode(HeatingMode Mode)
SetHeatingScheduleFromFile Method     string SetHeatingScheduleFromFile(System.IO.FileInfo FilePath)
SetHolidayMode             Method     string SetHolidayMode(datetime StartDateTime, datetime EndDateTime, int Temperature)
SetTemperature             Method     psobject SetTemperature(double targetTemperature)
ToString                   Method     string ToString()
ApiSessionId               Property   string ApiSessionId {get;set;}
ApiUrl                     Property   uri ApiUrl {get;set;}
Nodes                      Property   psobject Nodes {get;set;}
Password                   Property   string Password {get;set;}
User                       Property   psobject User {get;set;}
Username                   Property   string Username {get;set;}
#>
```

### Log in to the Hive API
Simply logs in to the Hive API. A session id is assigned by the Hive API that is used for subsequent communications and acts as your authorisation token.
```powershell
$h.Login() # Returns nothing but check $h.ApiSessionId for success.
```

### Get details about the nodes (devices)
Doesn't provide much useful information but I leave the method open for use for example so that you can implement your own logic based on the values of attributes. Use $h.Nodes (a call to GetClimate() is made regularly and stored in this class variable).
```powershell
$h.GetClimate() # Returns a [PSObject]
```

### Get the current temperature from Thermostat (formatted with symbols)
```powershell
$h.GetTemperature($true) # Returns 21.1°C
```
### Get the current temperature from Thermostat (unformatted)
```powershell
$h.GetTemperature($false) # Returns 21.1
```

### Set the temperature
Only works if heating mode is not currently **OFF**. Yes, I could turn the heating on in order to set the temperature but to what mode? That's up to you so I left this.
```powershell
$h.SetTemperature(21.5) # Returns "Desired temperature 21.5°C set successfully."
```

### Change the heating mode
Takes a parameter of type `[HeatingMode]` `OFF` | `MANUAL` | `SCHEDULE`
```powershell
$h.SetHeatingMode('OFF')
$h.SetHeatingMode('MANUAL')
$h.SetHeatingMode('SCHEDULE')
# Returns "Heating mode set to [mode] successfully."
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
# Returns "BOOST mode activated for [n] minutes at 22°C"
```

### Cancel a currently active boost
If the current heating mode is set to BOOST, turn it off. This reverts the system to its previous configuration using the `previousConfiguration` value stored for the Thermostat when BOOST was activated. ie. If it was MANUAL 20°C, it'll be returned to MANUAL 20°C.
```powershell
$h.CancelBoostMode() # Returns "Boost mode stopped."
```

### Enable Holiday mode
Turn on holiday mode. Requires a start and end date/time and temperature.
It's important to check that the date time format and region settings are correct on your PC. The start date shown below will be 1st August 2016 in UK format but 8th January in US format.
```powershell
$Start = Get-Date "01-08-2016 13:00" # So long as the date time is parseable!
$End = Get-Date "14-08-2016 14:00" # So long as the date time is parseable!
$Hive.SetHolidayMode($Start, $End, 13) # Returns "Holiday mode activated from 01/08/2016 13:00:00 -> 14/08/2016 14:00:00 @ 13°C."
```

### Cancel holiday mode
Cancels holiday mode.
```powershell
$Hive.CancelHolidayMode() # Returns "Holiday mode cancelled."
```

### Get holiday mode
Gets the current status of holiday mode.
```powershell
$Hive.GetHolidayMode() # Returns eg. (if enabled) "Holiday mode is enabled from 01/08/2016 13:00:00 -> 14/08/2016 14:00:00 @ 13°C."
```

### Get weather
Gets the current status of the outside weather for the location specified in the users' Hive website profile (postcode).
There is also an overload for GetWeather that allows you to enter a postcode. `$Hive.GetWeather([string] $Postcode)`
```powershell
$Hive.GetWeather() # Gets the weather for the users' location.
$Hive.GetWeather('SW1A 0AA') # Specific postcode location.

<# Returns [psobject]
description    temperature
-----------    -----------
Partly Cloudy  @{unit=C; value=5.0}
#>
```

### Save heating schedule to a file
Save the currently defined heating schedule to a file for editing.<br/>
**_Why?_** You could have different schedules for each season (Spring, Summer, Autumn, Winter) saved to files. Using `$h.SetHeatingScheduleFromFile()` you can implement your seasonal heating settings without fiddling with the website.<br/>*I'd like to see Hive implement this feature in the API actually. Having 4 heating profiles that can be saved to your user account/profile that can be recalled as required or scheduled to become active on certain dates (like the start of each season) - that's "smart".*
```powershell
$Hive.SaveHeatingScheduleToFile('D:\Temp\') # Returns nothing. A file containing the current heating schedule defined in JSON format is saved to D:\Temp\HiveSchedule-20160423-2212.json
```

### Set heating schedule from a file
Upload a heating schedule from a previously saved file. The method will parse the JSON structure to ensure it's valid and also check that there are 7 days worth of events in the schedule. It cannot however ensure that you are properly following all syntax. The best solution for creating your file is simply to set the schedule on the Hive website using the GUI and then use `$h.SaveHeatingScheduleToFile()` to save it. Repeat for all the profiles you want. If you want to edit the JSON, use any text editor but I recommend Notepad++ with the JSTool plugin.
```powershell
$h.SetHeatingScheduleFromFile('D:\Temp\winter-schedule.json') # Returns "Schedule set successfully from D:\Temp\winter-schedule.json"
```

### Log out
The session will automatically expire from the Hive API in approx 20 minutes but if you're performing just a few actions, log out anyway.
```powershell
$h.Logout() # Returns "Logged out successfully."
```

## Mentions
An honourable mention goes out to https://github.com/aklambeth for the inspiration and advising to implement using the v6 API.

## Questions?
If you have questions, comments, enhancement ideas etc. [post an issue.](https://github.com/lwsrbrts/PoSHive/issues)