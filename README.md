# PoSHive

A PowerShell class (supporting Windows PowerShell 5.1 or PowerShell Core 6.0+) to control your British Gas Hive system including the heating, hot water, multi zone, active plugs,  sensors and colour bulbs.

> **This project is not sanctioned by or affiliated with British Gas or Hive in any way.**

Install from the [PowerShell Gallery](https://www.powershellgallery.com/packages/PoSHive/)

```powershell
Install-Module -Name PoSHive -Scope CurrentUser
```

Or deploy to Azure Automation - yes, the class/module [will work within a runbook](https://github.com/lwsrbrts/PoSHive/wiki/AzureAutomationRunbook).

![alt-text](https://www.lewisroberts.com/wp-content/uploads/2016/04/poshive-runbook.png "PoSHive Runbook")

Or [download from the releases](https://github.com/lwsrbrts/PoSHive/releases) page.

## Release Notes

__Not all of the commands are covered in this read me (it's getting too long). Please see the [Wiki](wiki) for more information__

* [**2.3.0 - Colour Light**](https://github.com/lwsrbrts/PoSHive/releases/tag/v2.3.0) - 21/01/2018 - Support for Colour Lights (not tuneable).
* **2.2.0 - History** - 18/01/2018 - Added the ability to retrieve historical daily average temperature data from the Hive API up to 120 days in the past and produce either an object or a column chart using Google Charts for instant visualisation.
* [**2.1.0 - Sensing**](https://github.com/lwsrbrts/PoSHive/releases/tag/v2.1.0) - 04/08/2017 - Sensor support for both motion and contact sensors. Since there's no activities, these are just Get operations.
* [**2.0.0 - Hot zone**](https://github.com/lwsrbrts/PoSHive/releases/tag/v2.0.0) - 01/08/2017 - Finally added multi-zone and hot water support to the class!
* [**1.4.0 - Beekeeper**](https://github.com/lwsrbrts/PoSHive/releases/tag/v1.4.0) - 01/06/2017 - Updated to the new Beekeeper API that is used on the Hive website. With Hive going global (US) the endpoint may change per country so I've set the API endpoint from the returned data after login, just like the site. Added support for Active Plugs.
* [**1.3.1 - Someday**](https://github.com/lwsrbrts/PoSHive/releases/tag/v1.3.1) - 27/04/2016 - Bugfix. Issue preventing GetHolidayMode() method from returning a result.
* [**1.3.0 - Advance**](https://github.com/lwsrbrts/PoSHive/releases/tag/v1.3.0) - 25/04/2016 - Added method for advancing the heating system to the next event.
* [**1.2.0 - Scheduler**](https://github.com/lwsrbrts/PoSHive/releases/tag/v1.2.0) - 23/04/2016 - Methods for saving/setting heating schedules to/from a JSON file.
* **1.1.2 - Color[sic]** - 22/04/2016 - Removed the reliance on System.Drawing.Color assembly being loaded for use in this class. Moved it to PoSHue.
* **1.1.1 - User** - 22/04/2016 - User profile data (from the Hive site) is now an accessible class property ($h.User). Added methods to get outside weather conditions.
* **1.1.0 - Holiday** - 14/04/2016 - Added methods to get, set and cancel holiday mode. Fixed a bug preventing error messages returning useful information.
* **1.0.0 - Release** - 07/04/2016 - first release of the PoSHive class. Allows getting, setting temperature, setting heating mode to auto, manual or off. Turning on or cancelling of Boost mode.

## Purpose

The purpose of this class is to enable you to use PowerShell (v5) scripting to exert more powerful logic control over the state of your Hive system.
The class allows you to set most if not all of the same functionality as provided by the Hive website for your Hive system; including control of Heating, Multi-zone Heating, Hot Water, Active Plugs, Sensors, Schedules for each, as well as Holiday mode. Additionally, it allows you to more easily expose information about the system and its settings to enable you to perform powerful logic operations. If you find a bug or have a feature request, please open a new issue or let me know so I can resolve it.

## What can't it do

There's no support for:

* Tuneable Lights - support for Colour Lights was introduced in v2.3.0

## Examples

Some examples of use (and the reasons why I did this)

* Ask a weather service if it's Summer, turn the heating off completely.
* If it's Autumn, turn the Autumn schedule on (from a saved file)
* Automatically tweet the current temperature to you at 5pm. (Tweeting isn't implemented in this class, that's up to you!)
* If the temperature outside is less than 10 degrees, the inside temperature is less than 12 degrees and the heating is Off, turn it on for an hour at 20°C.
* Monitor tweets from a specific account (yours) and, so long as they're valid, set the temperature based on the tweet.
* Set your Philips Hue Light colour based on the current temperature inside or outside the home - why not use my PoSHue PowerShell class? ;)
* Have as many "on and off times" as you like - using Windows Task Scheduler, you're not limited by anything so primitive as 6 schedules a day! ;)

 ![alt-text](https://www.lewisroberts.com/wp-content/uploads/2016/04/poshivebasics130.gif "PoSHive basics")

Obviously these are example uses, this class simply provides the ability to control your heating system by abstracting the British Gas Hive Beekeeper API 1.0 in to PowerShell classes/methods.

## Using the class

### Install/download the class

The class is published on the [PowerShell Gallery](https://www.powershellgallery.com/packages/PoSHive/) site under the name `PoSHive`. This makes it simple to install.

```powershell
Install-Module -Name PoSHive
```

You can always just download the latest [release](https://github.com/lwsrbrts/PoSHive/releases) and copy the `PoSHive.ps1` file to an appropriate folder.

### Import the class in to PowerShell session

If you have installed the class from the PowerShell Gallery, use:

```powershell
Import-Module -Name PoSHive
```

If however you have copied the file to a folder, use:

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

Name                          MemberType Definition
----                          ---------- ----------
CancelBoostMode               Method     string CancelBoostMode(), string CancelBoostMode(string ZoneName)
CancelHolidayMode             Method     string CancelHolidayMode()
CancelHotWaterBoostMode       Method     string CancelHotWaterBoostMode()
Equals                        Method     bool Equals(System.Object obj)
GetActivePlugPowerConsumption Method     int GetActivePlugPowerConsumption(string Name)
GetActivePlugState            Method     bool GetActivePlugState(string Name)
GetColourBulb                 Method     psobject GetColourBulb(string Name)
GetColourBulbConfig           Method     psobject GetColourBulbConfig(string Name)
GetContactSensorState         Method     psobject GetContactSensorState(string SensorName, bool IncludeTodaysEvents)
GetDevices                    Method     psobject GetDevices()
GetHashCode                   Method     int GetHashCode()
GetHeatingHistory             Method     psobject GetHeatingHistory(datetime StartDate, datetime EndDate, string ZoneName), psobject GetHeatingHistory(datetime StartDate, datetime EndDate, string ZoneName, System.IO.DirectoryInfo DirectoryPath)
GetHeatingState               Method     bool GetHeatingState(string ZoneName)
GetHolidayMode                Method     string GetHolidayMode()
GetMotionSensorState          Method     psobject GetMotionSensorState(string SensorName, bool IncludeTodaysEvents)
GetProducts                   Method     psobject GetProducts()
GetTemperature                Method     psobject GetTemperature(bool FormattedValue), psobject GetTemperature(string ZoneName, bool FormattedValue)
GetType                       Method     type GetType()
GetWeather                    Method     psobject GetWeather(), psobject GetWeather(string Postcode, string CountryCode)
GetWeatherTemperature         Method     int GetWeatherTemperature()
Login                         Method     void Login()
Logout                        Method     psobject Logout()
SaveActivePlugScheduleToFile  Method     void SaveActivePlugScheduleToFile(System.IO.DirectoryInfo DirectoryPath, string Name)
SaveHeatingScheduleToFile     Method     void SaveHeatingScheduleToFile(System.IO.DirectoryInfo DirectoryPath), void SaveHeatingScheduleToFile(string ZoneName, System.IO.DirectoryInfo DirectoryPath)
SaveHotWaterScheduleToFile    Method     void SaveHotWaterScheduleToFile(System.IO.DirectoryInfo DirectoryPath)
SetActivePlugMode             Method     string SetActivePlugMode(DeviceMode Mode, string Name)
SetActivePlugScheduleFromFile Method     string SetActivePlugScheduleFromFile(System.IO.FileInfo FilePath, string Name)
SetActivePlugState            Method     string SetActivePlugState(bool State, string Name)
SetBoostMode                  Method     psobject SetBoostMode(BoostTime Duration), psobject SetBoostMode(string ZoneName, BoostTime Duration)
SetColourBulbColour           Method     psobject SetColourBulbColour(string Name, int Hue, int Saturation, int Brightness)
SetColourBulbMode             Method     string SetColourBulbMode(DeviceMode Mode, string Name)
SetColourBulbState            Method     string SetColourBulbState(bool State, string Name)
SetColourBulbWhite            Method     psobject SetColourBulbWhite(string Name, int Temperature, int Brightness)
SetHeatingAdvance             Method     string SetHeatingAdvance(), string SetHeatingAdvance(string ZoneName)
SetHeatingMode                Method     psobject SetHeatingMode(HeatingMode Mode), psobject SetHeatingMode(string ZoneName, HeatingMode Mode)
SetHeatingScheduleFromFile    Method     string SetHeatingScheduleFromFile(System.IO.FileInfo FilePath), string SetHeatingScheduleFromFile(string ZoneName, System.IO.FileInfo FilePath)
SetHolidayMode                Method     string SetHolidayMode(datetime StartDateTime, datetime EndDateTime, int Temperature)
SetHotWaterBoostMode          Method     psobject SetHotWaterBoostMode(BoostTime Duration)
SetHotWaterMode               Method     psobject SetHotWaterMode(HeatingMode Mode)
SetHotWaterScheduleFromFile   Method     string SetHotWaterScheduleFromFile(System.IO.FileInfo FilePath)
SetTemperature                Method     psobject SetTemperature(double targetTemperature), psobject SetTemperature(string ZoneName, double targetTemperature)
ToString                      Method     string ToString()
ApiSessionId                  Property   string ApiSessionId {get;set;}
ApiUrl                        Property   uri ApiUrl {get;set;}
Devices                       Property   psobject Devices {get;set;}
Password                      Property   securestring Password {get;set;}
Products                      Property   psobject Products {get;set;}
User                          Property   psobject User {get;set;}
Username                      Property   string Username {get;set;}
#>
```

### Log in to the Hive API

Simply logs in to the Hive API. A session id is assigned by the Hive API that is used for subsequent communications and acts as your authorisation token.

```powershell
$h.Login() # Returns nothing but check $h.ApiSessionId for success.
```

### Get details about the products (devices)

Doesn't provide much useful information but I leave the method open for use for example so that you can implement your own logic based on the values of attributes. Use $h.Products (a call to GetProducts() is made regularly and stored in this class variable).

```powershell
$h.GetProducts() # Returns a [PSObject]
```

### Get details about the devices (battery state, IP etc.)

Doesn't provide much useful information but I leave the method open for use for example so that you can implement your own logic based on the values of attributes. Use $h.Devices (a call to GetDevices() is made regularly and stored in this class variable).

```powershell
$h.GetDevices() # Returns a [PSObject]
```

### Get the current temperature from Thermostat (formatted with symbols) (single-zone system)

```powershell
$h.GetTemperature($true) # Returns 21.1°C
```

### Get the current temperature from the named zone's thermostat (formatted with symbols) (multi-zone system)

```powershell
$h.GetTemperature('FirstFloor', $true) # Returns 21.1°C
```

### Get the current temperature from Thermostat (unformatted) (single-zone system)

```powershell
$h.GetTemperature($false) # Returns 21.1
```

### Get the current temperature from the named zone's thermostat (unformatted) (multi-zone system)

```powershell
$h.GetTemperature('FirstFloor', $false) # Returns 21.1
```

### Set the temperature

Only works if heating mode is not currently **OFF**. Yes, I could turn the heating on in order to set the temperature but to what mode? That's up to you so I left this.

```powershell
$h.SetTemperature(21.5) # Single-zone - returns "Desired temperature 21.5°C set successfully."
$h.SetTemperature('FirstFloor', 21.5) # Multi-zone - returns "Desired temperature 21.5°C set successfully."
```

### Change the heating mode

Takes a parameter of type `[HeatingMode]` `OFF` | `MANUAL` | `SCHEDULE`

```powershell
$h.SetHeatingMode('OFF')
$h.SetHeatingMode('MANUAL')
$h.SetHeatingMode('SCHEDULE')
# Returns "Heating mode set to [mode] successfully in a single-zone system."
$h.SetHeatingMode('FirstFloor', 'OFF')
$h.SetHeatingMode('FirstFloor', 'MANUAL')
$h.SetHeatingMode('FirstFloor', 'SCHEDULE')
# Returns "Heating mode set to [mode] successfully in a multi-zone system."
```

### Boost the heating system for the defined time

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
$h.SetBoostMode('FirstFloor', 'HALF') # Returns "BOOST mode activated for [n] minutes at 22°C ina  multi-zone system."
```

### Cancel a currently active boost

If the current heating mode is set to BOOST, turn it off. This reverts the system to its previous configuration using the `previousConfiguration` value stored for the Thermostat when BOOST was activated. ie. If it was MANUAL 20°C, it'll be returned to MANUAL 20°C.

```powershell
$h.CancelBoostMode() # Returns "Boost mode stopped in a single-zone system."
$h.CancelBoostMode('FirstFloor') # Returns "Boost mode stopped in a multi-zone system."
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

Save the currently defined heating schedule to a file for editing.

**_Why?_** You could have different schedules for each season (Spring, Summer, Autumn, Winter) saved to files. Using `$h.SetHeatingScheduleFromFile()` you can implement your seasonal heating settings without fiddling with the website.*I'd like to see Hive implement this feature in the API actually. Having 4 heating profiles that can be saved to your user account/profile that can be recalled as required or scheduled to become active on certain dates (like the start of each season) - that's "smart".*

```powershell
$Hive.SaveHeatingScheduleToFile('D:\Temp\') # Returns nothing. A file containing the current heating schedule defined in JSON format is saved to D:\Temp\HiveSchedule-20160423-2212.json
$Hive.SaveHeatingScheduleToFile('FirstFloor', 'D:\Temp\') # Multi-zone
```

### Set heating schedule from a file

Upload a heating schedule from a previously saved file. The method will parse the JSON structure to ensure it's valid and also check that there are 7 days worth of events in the schedule. It cannot however ensure that you are properly following all syntax. The best solution for creating your file is simply to set the schedule on the Hive website using the GUI and then use `$h.SaveHeatingScheduleToFile()` to save it. Repeat for all the profiles you want. If you want to edit the JSON, use any text editor but I recommend either Visual Studio Code or Notepad++ with the JSTool plugin.

```powershell
$h.SetHeatingScheduleFromFile('D:\Temp\winter-schedule.json') # Returns "Schedule set successfully from D:\Temp\winter-schedule.json"
$h.SetHeatingScheduleFromFile('FirstFloor', 'D:\Temp\winter-schedule.json') # Multi-zone
```

### Advance

Just like the Hive site, this method advances the heating system to the next event in the schedule (for example if you want to turn the heating on (or off!) a little earlier than the schedule permits). The heating mode of the system MUST be schedule or the method returns an error.

```powershell
$h.SetHeatingAdvance()
$h.SetHeatingAdvance('FirstFloor') # Multi-zone
<#
"Advancing to 17.0°C
Desired temperature 17°C set successfully."
#>
```

### Change the hot water mode

Takes a parameter of type `[HeatingMode]` `OFF` | `MANUAL` | `SCHEDULE`

```powershell
$h.SetHotWaterMode('OFF')
$h.SetHotWaterMode('MANUAL')
$h.SetHotWaterMode('SCHEDULE')
# Returns "Hot water mode set to [mode] successfully."
```

### Boost the hot water for the defined time

Takes a parameter of type `[BoostTime]` `HALF` | `ONE` | `TWO` | `THREE` | `FOUR` | `FIVE` | `SIX` which is based on hours and converted to minutes before being submitted to the API. I haven't used an `[int]` type because the API does mention these values specifically so it's best to enforce their use.

```powershell
$h.SetHotWaterBoostMode('HALF')
$h.SetHotWaterBoostMode('ONE')
$h.SetHotWaterBoostMode('TWO')
$h.SetHotWaterBoostMode('THREE')
$h.SetHotWaterBoostMode('FOUR')
$h.SetHotWaterBoostMode('FIVE')
$h.SetHotWaterBoostMode('SIX')
```

### Cancel a currently active hot water boost

If the current hot water mode is set to BOOST, turn it off. This reverts the system to its previous configuration using the `previousConfiguration` value stored for the hot water when BOOST was activated. ie. If it was OFF, it'll be returned to OFF.

```powershell
$h.CancelHotWaterBoostMode() # Returns "Hot water BOOST cancelled."
```

### Save hot water schedule to a file

Save the currently defined hot water schedule to a file for editing.

```powershell
$Hive.SaveHotWaterScheduleToFile('D:\Temp\') # Returns nothing. A file containing the current hot water schedule defined in JSON format is saved to D:\Temp\HiveHotWaterSchedule-20160423-2212.json
```

### Set hot water schedule from a file

Upload a hot water schedule from a previously saved file. The method will parse the JSON structure to ensure it's valid and also check that there are 7 days worth of events in the schedule. It cannot however ensure that you are properly following all syntax. The best solution for creating your file is simply to set the schedule on the Hive website using the GUI and then use `$h.SaveHotWaterScheduleToFile()` to save it. Repeat for all the profiles you want. If you want to edit the JSON, use any text editor but I recommend either Visual Studio Code or Notepad++ with the JSTool plugin.

```powershell
$h.SetHotWaterScheduleFromFile('D:\Temp\HiveHotWaterSchedule-20160423-2212.json') # Returns "Schedule set successfully from D:\Temp\HiveHotWaterSchedule-20160423-2212.json"
```

### Set Active Plug mode

Enables schedule or manual mode for an Active Plug by its known name. Takes a parameter of type `[ActivePlugMode]` `MANUAL` | `SCHEDULE`
If a plug is set to schedule mode when there is an "on" event, the plug will turn on as per the schedule. If you subsequently set the plug back to manual, it will remain in the on state.

```powershell
$h.SetActivePlugMode('MANUAL', 'Plug 1')
$h.SetActivePlugMode('SCHEDULE', 'Fan')
<#
Active Plug "Plug 1" set to MANUAL successfully.
Active Plug "Fan" set to SCHEDULE successfully.
#>
```

### Set Active Plug state

Turns an Active Plug on or off, irrespective of the current mode (manual or schedule).

```powershell
$h.SetActivePlugState($true, 'Plug 1')
$h.SetActivePlugState($false, 'Fan')
<#
Active Plug "Plug 1" set to ON successfully.
Active Plug "Fan" set to OFF successfully.
#>
```

### Get current power consumption (in watts)

Gets the current power consumption (in watts) of the device attached to the Active Plug.

This is handy for monitoring usage. For example, an auto-sensing clothes dryer that stays on for an indeterminate amount of time can be turned off completely when the value falls to a low number (indicating it has finished the drying cycle).

_This methos is of particular interest to me since I have an auto-sensing dryer which, once it has finished the drying cycle, continues to make an annoying beeping noise every 30 seconds until you open the door or turn it off, meaning it can't be used before going to bed._

```powershell
$h.GetActivePlugPowerConsumption('Plug 1') # Returns eg. "33"
```

### Get the state of a motion sensor

Gets the current state of a named motion sensor including, if desired, the latest event and today's events.

```powershell
$h.GetMotionSensorState('Motion Sensor 1', $true) # Returns a psobject with sensor state and today's history events.
$h.GetMotionSensorState('Motion Sensor 1', $false) # Returns a psobject with sensor state only.
```

### Get the state of a contact (window/door) sensor

Gets the current state of a named contact sensor including, if desired, the latest event and today's events.

```powershell
$h.GetContactSensorState('Win/Door Sensor 1', $true) # Returns a psobject with sensor state and today's history events.
$h.GetContactSensorState('Win/Door Sensor 1', $true) # Returns a psobject with sensor state only.
```

### Log out

The session will automatically expire from the Hive API in approx 20 minutes but if you're performing just a few actions, log out anyway.

```powershell
$h.Logout() # Returns "Logged out successfully."
```

## Mentions

An honourable mention goes out to [https://github.com/aklambeth](https://github.com/aklambeth) for the inspiration and advising to implement using the v6 API.

## Questions

If you have questions, comments, enhancement ideas etc. [post an issue.](https://github.com/lwsrbrts/PoSHive/issues)