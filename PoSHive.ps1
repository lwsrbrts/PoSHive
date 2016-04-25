Enum HeatingMode {
    <# Defines the heating modes that can be set. #>
    SCHEDULE
    MANUAL
    OFF
}

Enum BoostTime {
    <# Defines accepted boost durations in hours. #>
    HALF
    ONE
    TWO
    THREE
    FOUR
    FIVE
    SIX
}

Class Hive {
    ##############
    # PROPERTIES #
    ##############

    [uri]$ApiUrl = "https://api-prod.bgchprod.info/omnia/" # APIv6.1
    [ValidateLength(4,100)][string] $Username
    [ValidateLength(4,100)][string] $Password
    [string] $ApiSessionId
    hidden [string] $Agent = 'PoSHive 1.3.0 - github.com/lwsrbrts/PoSHive'
    [psobject] $User
    [psobject] $Nodes
    hidden [hashtable] $Headers = @{
        'Accept' = 'application/vnd.alertme.zoo-6.1+json'
        'X-AlertMe-Client' = $this.Agent
        'Content-Type' = 'application/json'
    }
    
    ###############
    # CONSTRUCTOR #
    ###############

    Hive([string] $Username, [string] $Password) {
        $this.Username = $Username
        $this.Password = $Password
    }

    ###########
    # METHODS #
    ###########

    # Convert Unix time in milliseconds to local datetime object.
    hidden [datetime] ConvertUnixTime([long] $Milliseconds) {
        Return [System.DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds).LocalDateTime
    }

    # Return errors and terminate execution 
    hidden [void] ReturnError([System.Management.Automation.ErrorRecord] $e) {
        $sr = [System.IO.StreamReader]::new($e.Exception.Response.GetResponseStream())
        $sr.BaseStream.Position = 0
        $r = ConvertFrom-Json ($sr.ReadToEnd())
        Write-Error "An error occurred in the execution of the request:`r`nError Code:`t$($r.errors.code)`r`nError Title:`t$($r.errors.title)" -ErrorAction Stop
    }

    # Return errors and terminate execution 
    hidden [void] ReturnError([string] $e) {
        Write-Error $e -ErrorAction Stop
    }

    # Login - could do this in the constructor but makes sense to have it as a separate method. May only want weather!
    [void] Login () {
        $Settings = [psobject]@{
            sessions = @(
                @{
                    username = $this.Username
                    password = $this.Password
                }
             )
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/auth/sessions" -Body (ConvertTo-Json $Settings) -Headers $this.Headers -ErrorAction Stop
            $this.ApiSessionId = $Response.sessions.id
            $this.Headers.Add('X-Omnia-Access-Token', $this.ApiSessionId)
            $this.Nodes = $this.GetClimate()
            $this.User = $this.GetUser()
        }
        Catch {
            $this.ReturnError($_)
        }
    }

    # Log out - essentially deletes the ApiSession from the API and nulls the ApiSessionId
    [psobject] Logout() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Response = Invoke-RestMethod -Method Delete -Uri "$($this.ApiUrl)/auth/sessions/$($this.ApiSessionId)" -Headers $this.Headers
            # Needs some error checking.
            $this.ApiSessionId = $null
            $this.Headers.Remove('X-Omnia-Access-Token')
            Return "Logged out successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Get nodes (devices) data.
        Still exposed as a usable method in the class but acts primarily
        as a helper method to keep the $this.Nodes variable fresh. Is usually called
        before any setting method that includes logic or is dependent on the state
        of an attribute.
    #>
    [psobject] GetClimate() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/nodes" -Headers $this.Headers -ErrorAction Stop
            Return $Response.nodes
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }
    #>

    <#
        Does what it says on the tin. Returns the currently reported temperature
        value from the thermostat. Not likely to work as expected in multi-zone/thermostat
        Hive systems. Sorry.
        Provide $true to get a formatted value: eg. 21.1°C
        Provide $false to get a simple decimal: eg. 21.1
    #>
    [psobject] GetTemperature([bool] $FormattedValue) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $this.Nodes = $this.GetClimate()
            $Temperature = [Math]::Round($this.Nodes.attributes.temperature.reportedValue, 1)
            If ($FormattedValue) {Return "$($Temperature.ToString())$([char] 176 )C"}
            Else {Return $Temperature}
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Sets the heating mode to one of the [HeatingMode] enum values. ie.
        SCHEDULE, MANUAL, OFF. $this.Nodes is always refreshed prior to execution.
        This method does not identify the Thermostat on which to set the mode,
        it only sets it on the first returned thermostat in the system. (Identified by
        the existence of the targetHeatTemperature attribute on a device).
        It therefore DOES NOT support multi-zone/thermostat Hive installations, sorry!
    #>
    [psobject] SetHeatingMode([HeatingMode] $Mode) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Nodes = $this.GetClimate()
        
        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        $ApiMode = $null
        $ApiScheduleLock = $null
        Switch ($Mode)
        {
            'MANUAL' {$ApiMode = 'HEAT'; $ApiScheduleLock = $true}
            'SCHEDULE' {$ApiMode = 'HEAT'; $ApiScheduleLock = $false}
            'OFF' {$ApiMode = 'OFF'; $ApiScheduleLock = $true}
        }
        $Settings = [psobject]@{
            nodes = @(
                @{
                    attributes = @{
                        activeHeatCoolMode = @{targetValue = $ApiMode}
                        activeScheduleLock = @{targetValue = $ApiScheduleLock}
                    }
                }
            )
        }

        Try {
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Heating mode set to $($Mode.ToString()) successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
        
    }

    <#
        Sets the temperature value on the first thermostat device in the system.
        $this.Nodes is always refreshed prior to execution.
        This method does not identify the thermostat on which to set the temperature.
        It only sets it on the first returned thermostat in the system. (Identified by
        the existence of the targetHeatTemperature attribute on a device).
        It therefore DOES NOT support multi-zone/thermostat Hive installations, sorry!
    #>
    [psobject] SetTemperature([double] $targetTemperature) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Get a sensible temp from the input value rounded to nearest half degree
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Update nodes
        $this.Nodes = $this.GetClimate()

        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        # Check the submitted temp doesn't exceed the permitted values
        If (($Temp -gt $Thermostat.attributes.maxHeatTemperature.reportedValue) -or ($Temp -lt $Thermostat.attributes.minHeatTemperature.reportedValue)) {
            $this.ReturnError("Submitted temperature value ($Temp) exceeds the permitted range ($($Thermostat.attributes.minHeatTemperature.reportedValue) -> $($Thermostat.attributes.maxHeatTemperature.reportedValue))")
        }

        # Check the heating is not in OFF state
        If ($Thermostat.attributes.activeHeatCoolMode.reportedValue -eq 'OFF') {
            $this.ReturnError("Heating mode is currently OFF. Set to MANUAL or SCHEDULE first.")
        }

        # This will be converted to JSON. I suppose it could just be JSON but...meh.
        $Settings = [psobject]@{
            nodes = @(
                @{
                    attributes = @{targetHeatTemperature = @{targetValue = $Temp}}
                }
             )
        }
        Try {
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Desired temperature ($($targetTemperature.ToString())$([char] 176 )C) set successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Boosts the heating system for the defined time.
        The [BoostTime] Enum is used to ensure proper time values are submitted.
        Always boosts to 22°C - this is the same as the Hive site.
        You can re-boost at any time but the timer starts again, obviously.
    #>
    [psobject] SetBoostMode([BoostTime] $Duration) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Nodes = $this.GetClimate()

        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        $ApiDuration = $null # Creating so it's there!
        $ApiTemperature = 22 # This is the same Boost default temp as the Hive site.

        Switch ($Duration) {
            'HALF' {$ApiDuration = 30}
            'ONE' {$ApiDuration = 60}
            'TWO' {$ApiDuration = 120}
            'THREE' {$ApiDuration = 180}
            'FOUR' {$ApiDuration = 240}
            'FIVE' {$ApiDuration = 300}
            'SIX' {$ApiDuration = 360}
        }

        # JSON structure in a PSObject
        $Settings = [psobject]@{
            nodes = @(
                @{
                    attributes = @{
                        activeHeatCoolMode = @{targetValue = 'BOOST'}
                        scheduleLockDuration = @{targetValue = $ApiDuration}
                        targetHeatTemperature = @{targetValue = $ApiTemperature}
                    }
                }
             )
        }

        Try {
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "BOOST mode activated for $ApiDuration minutes at $($ApiTemperature.ToString())$([char] 176 )C"
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        If the current heating mode is set to BOOST, turn it off.
        This reverts the system to its previous configuration using the
        previousConfiguration value stored for the Thermostat when
        BOOST was activated.
    #>
    [string] CancelBoostMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Find out the correct node for the Thermostat.
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        # If the system isn't set to BOOST, return without doing anything.
        If ($Thermostat.attributes.activeHeatCoolMode.reportedValue -ne 'BOOST') {
            $this.ReturnError("The current heating mode is not BOOST.")
        }
        
        Switch ($Thermostat.attributes.previousConfiguration.reportedValue.mode) {
            AUTO { $this.SetHeatingMode('SCHEDULE') }
            MANUAL {
                $this.SetHeatingMode('MANUAL')
                $this.SetTemperature($Thermostat.attributes.previousConfiguration.reportedValue.targetHeatTemperature)
            }
            OFF { $this.SetHeatingMode('OFF') }
            Default {$this.SetHeatingMode('SCHEDULE')}
        }

        Return "Boost mode stopped."
    }

    # Get information about current holiday mode
    [string] GetHolidayMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Find out the correct destination for holiday mode settings.
        $Receiver = $this.Nodes | Where-Object {$_.attributes.holidayMode.targetValue} | Select -First 1
        $Holiday = $Receiver.attributes.holidayMode

        #Init variables...
        $Start = $End = $Temp = $null

        If ($Holiday.reportedValue.enabled -eq $true) {
            $Start = [DateTime]::SpecifyKind($Holiday.reportedValue.startDateTime, [DateTimeKind]::Utc)
            $End = [DateTime]::SpecifyKind($Holiday.reportedValue.endDateTime, [DateTimeKind]::Utc)
            $Temp = [int] $Holiday.targetValue.targetHeatTemperature
        }
        ElseIf ($Holiday.reportedValue.enabled -eq $false) {
            Return "Holiday mode is not currently enabled."
        }
        Else {
            $this.ReturnError("Unable to determine the current settings of holiday mode.")
        }

        Return "Holiday mode is enabled from $($Start.ToLocalTime().ToString()) -> $($End.ToLocalTime().ToString()) @ $Temp$([char]176)C."        
    }

    
    # Enable holiday mode, providing a start and end date and temperature
    [string] SetHolidayMode([datetime] $StartDateTime, [datetime] $EndDateTime, [int] $Temperature) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Ensure date times are correctly stated.
        If ($StartDateTime -lt (Get-Date)) {$this.ReturnError("Start date and time is in the past.")}
        If ($EndDateTime -lt (Get-Date)) {$this.ReturnError("End date and time is in the past.")}
        If ($EndDateTime -lt $StartDateTime) {$this.ReturnError("End date is before start date.")}

        # Check the user didn't type the wrong temp value.
        If ($Temperature -notin 1..32) {
            $this.ReturnError("Your chosen holiday mode temperature exceeds the acceptable range (1$([char]176)C -> 32$([char]176)C)")
        }
        
        # Check the submitted temp doesn't exceed the permitted values
        If ($Temperature -ge 15) {
            Write-Warning -Message "Your chosen holiday temperature ($Temperature$([char]176)C) is quite warm. To change it, send the request again."
        }

        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Find out the correct destination for holiday mode settings.
        $Receiver = $this.Nodes | Where-Object {$_.attributes.holidayMode.targetValue} | Select -First 1

        # The user will only ever define a local time but force it anyway.
        $StartDateUTC = [DateTime]::SpecifyKind($StartDateTime, [DateTimeKind]::Local)
        $EndDateUTC = [DateTime]::SpecifyKind($EndDateTime, [DateTimeKind]::Local)

        $Settings = [psobject]@{
            nodes = @(
                @{
                    attributes = @{
                        holidayMode = @{
                            targetValue = @{ 
                                enabled = $true
                                targetHeatTemperature = $Temperature
                                startDateTime = (Get-Date $StartDateUTC -Format "yyyy-MM-ddTHH:mm:ssK")
                                endDateTime = (Get-Date $EndDateUTC -Format "yyyy-MM-ddTHH:mm:ssK")
                            }
                        }
                    }
                }
            )
        }

        Try {
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Receiver.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Holiday mode activated from $($StartDateTime.ToString()) -> $($EndDateTime.ToString()) @ $Temperature$([char]176)C."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    # Cancel holiday mode.
    [string] CancelHolidayMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Find out the correct destination for holiday mode settings.
        $Receiver = $this.Nodes | Where-Object {$_.attributes.holidayMode.targetValue} | Select -First 1

        $Settings = [psobject]@{
            nodes = @( @{ attributes = @{ holidayMode = @{ targetValue = @{ enabled = $false } } } } )
        }

        Try {
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Receiver.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Holiday mode cancelled."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    # Get user information for the logged in user. Data requested once at login time.
    [psobject] GetUser() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/users/" -Headers $this.Headers
            Return $Response.users[0]
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    # Get the current weather (temp, conditions) for the users' postcode location.
    [psobject] GetWeather() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        $Postcode = $this.User.postcode
        
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "https://weather-prod.bgchprod.info/weather?postcode=$Postcode"
            Return $Response.weather | Select description, temperature
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    # Get the current weather (temp, conditions) for a specific postcode location.
    # Make sure the postcode is accurate or you'll likely get an error. I don't validate it!
    [psobject] GetWeather([string] $Postcode) {
        $Postcode = $Postcode.Replace(' ', '').ToUpper()
        
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "https://weather-prod.bgchprod.info/weather?postcode=$Postcode"
            Return $Response.weather | Select description, temperature
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    # Get the outside weather temperature for the users' postcode location in °C
    [int] GetWeatherTemperature() {
        Return $this.GetWeather().temperature.value
    }

    # Use this method to save your current schedule (as set on the Hive site) to a file.
    # Specify a directory only - the file will be named HiveSchedule-yyyyMMddHHmm.json
    [void] SaveHeatingScheduleToFile([System.IO.DirectoryInfo] $DirectoryPath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not $DirectoryPath.Exists) {$this.ReturnError("The path should already exist.")}

        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Get the node that holds the schedule data.
        # This really will not work for hot water!
        $Receiver = $this.Nodes | Where-Object {$_.attributes.schedule}

        # Create the correct json structure.
        $Settings = [psobject]@{
            nodes = @( @{ attributes = @{ schedule = @{ targetValue = $Receiver.attributes.schedule.reportedValue } } } )
        }

        # Create the file output path and name.
        $File = [System.IO.Path]::Combine($DirectoryPath, "HiveSchedule-$(Get-Date -Format "yyyyMMdd-HHmm").json")

        # Save the file to disk or error if it exists - let the user handle renaming/moving/deleting.
        Try {
            ConvertTo-Json -InputObject $Settings -Depth 99 | Out-File -FilePath $File -NoClobber
        }
        Catch {
            $this.ReturnError("An error occurred saving the file.`r`n$_")
        }
    }

    # Reads in a JSON file containing heating schedule data. It is recommended to save a copy of your current
    # schedule first using SaveHeatingScheduleToFile('C:\')
    [string] SetHeatingScheduleFromFile([System.IO.FileInfo] $FilePath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not (Test-Path -Path $FilePath )) {$this.ReturnError("The file path supplied does not exist.")}

        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Get the node that holds the schedule data.
        # This really will not work for hot water!
        $Receiver = $this.Nodes | Where-Object {$_.attributes.schedule}

        $Settings = $null
        
        # Read in the schedule data from the file.
        Try {
            $Settings = ConvertFrom-Json -InputObject (Get-Content -Path $FilePath -Raw)
        }
        Catch {
            $this.ReturnError("The file specified could not be parsed as valid JSON.`r`n$_")
        }

        # Seven days of events in the file?
        If (((($Settings.nodes.attributes.schedule.targetValue).psobject.Members | Where {$_.MemberType -eq 'NoteProperty'}).count) -eq 7) {
            Try {
                $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/nodes/$($Receiver.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
                Return "Schedule set successfully from $FilePath"
            }
            Catch {
                $this.ReturnError($_)
                Return $null
            }
        }
        Else {Return "The schedule in the file must contain entries for all seven days."}
    }

    [string] SetHeatingAdvance() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes data
        $this.Nodes = $this.GetClimate()

        # Get the node that holds the schedule data.
        # This really will not work for hot water!
        $Receiver = $this.Nodes | Where-Object {$_.attributes.schedule}

        # Check the heating is in SCHEDULE mode.
        If (-not (($Receiver.attributes.activeHeatCoolMode.reportedValue -eq 'HEAT') -and ($Receiver.attributes.activeScheduleLock.reportedValue -eq $false))) {
            $this.ReturnError("Heating mode is not currently SCHEDULE. Advancing is not possible.")
        }

        # Get the schedule data
        $Schedule = $Receiver.attributes.schedule.reportedValue

        # Get the current date and time.
        $Date = Get-Date

        # Set up variables.
        $NextEvent = $null
        
        # Get today's schedule
        $DaySchedule = Select-Object -InputObject $Schedule -ExpandProperty $Date.DayOfWeek.ToString()

        # Get the next period/schedule from today's events
        Foreach ($Period in $DaySchedule) {
            If ((Get-Date $Period.time) -gt $Date) {
                $NextEvent = $Period
                Break
            }
        }

        # If there is no event from today that's ahead of now, get tomorrow's first event.
        If (-not $NextEvent) {
            $DaySchedule = Select-Object -InputObject $Schedule -ExpandProperty $Date.AddDays(1).DayOfWeek.ToString()
            $NextEvent = $DaySchedule[0]
        }

        # Set the temperature to the next event.
        Return "Advancing to $($NextEvent.targetHeatTemperature)$([char]176)C...`r`n$($this.SetTemperature($NextEvent.targetHeatTemperature))"
    }

# END HIVE CLASS
}