Enum HeatingMode {
    <# Defines the heating modes that can be set. #>
    SCHEDULE
    MANUAL
    OFF
}

Enum ActivePlugMode {
    <# Defines the modes that can be set on an active plug. #>
    SCHEDULE
    MANUAL
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

    [uri]$ApiUrl = "https://beekeeper.hivehome.com/1.0/global/login" # This is the global login URL - changes after login.
    [ValidateLength(4,100)][string] $Username
    [securestring] $Password
    [string] $ApiSessionId
    hidden [string] $Agent = 'PoSHive 2.1.1 - github.com/lwsrbrts/PoSHive'
    [psobject] $User
    [psobject] $Devices
    [psobject] $Products
    hidden [hashtable] $Headers = @{
        'Accept' = '*/*'
        'User-Agent' = $this.Agent
        'Content-Type' = 'application/json'
    }
    
    ###############
    # CONSTRUCTOR #
    ###############

    Hive([string] $Username, [string] $Password) {
        $this.Username = $Username
        $this.Password = ConvertTo-SecureString -String $Password -AsPlainText -Force
    }

    ###########
    # METHODS #
    ###########

    # Convert Unix time in milliseconds to local datetime object.
    hidden [datetime] ConvertUnixTime([long] $Milliseconds) {
        Return [System.DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds).LocalDateTime
    }

    # Convert date time to unix time in milliseconds.
    hidden [long] DateTimeToUnixTimestamp ([datetime] $dateTime) {
        Return ($dateTime.ToUniversalTime() - [datetime]::new(1970, 1, 1, 0, 0, 0, 0, [DateTimeKind]::Utc)).TotalMilliseconds
    }

    # Decrypt a securestring back to plain text.
    hidden [string] DecryptSecureString ([System.Security.SecureString] $SecureString) {
        $PlainString = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))
        Return $PlainString
    }

    # Return errors and terminate execution
    <#
    hidden [void] ReturnError([System.Management.Automation.ErrorRecord] $e) {
        $sr = [System.IO.StreamReader]::new($e.Exception.Response.GetResponseStream())
        $sr.BaseStream.Position = 0
        $r = ConvertFrom-Json ($sr.ReadToEnd())
        Write-Error "An error occurred in the execution of the request:`r`nError Code:`t$($r.errors.code)`r`nError Title:`t$($r.errors.title)" -ErrorAction Stop
    }
    #>

    # Return errors and terminate execution 
    hidden [void] ReturnError([string] $e) {
        Write-Error $e -ErrorAction Stop
    }

    # Login - could do this in the constructor but makes sense to have it as a separate method. May only want weather!
    [void] Login () {
        If ($this.ApiSessionId) {$this.ReturnError("You are already logged in.")}

        $Settings = [psobject]@{
            username = $this.Username
            password = ($this.DecryptSecureString($this.Password))
            devices = $true
            products = $true
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri $this.ApiUrl -Body (ConvertTo-Json $Settings) -Headers $this.Headers -ErrorAction Stop
            $this.ApiSessionId = $Response.token
            $this.Headers.Add('Authorization', $this.ApiSessionId)
            $this.ApiUrl = $Response.platform.endpoint
            $this.Devices = $Response.devices
            $this.Products = $Response.products
            $this.User = $Response.user
        }
        Catch {
            $this.ReturnError($_)
        }
    }

    # Log out - essentially deletes the ApiSession from the API and nulls the ApiSessionId
    [psobject] Logout() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Response = Invoke-RestMethod -Method Delete -Uri "$($this.ApiUrl)/auth/logout" -Headers $this.Headers -ErrorAction Stop
            Write-Output "Logged out successfully."
        }
        Catch [System.Net.WebException] {
            If ($_.Exception.Response.StatusCode.value__ -eq 401) {
                Write-Output "Your session was not found on the remote server so your local session was reset."
            }
            Else { Write-Output "An error occurred when communicating with the remote server. Your session was reset." }
            Return $_.Exception.Message
        }
        Catch {
            Write-Output "An error occurred when communicating with the remote server. Your session was reset."
            Return $_.Exception.Message
        }
        Finally {
            $this.ApiSessionId = $null
            $this.Headers.Remove('Authorization')
            $this.ApiUrl = "https://beekeeper.hivehome.com/1.0/global/login" # Reset the login URL.
        }
        Return $null
    }

    <#
        Get products data.
        Still exposed as a usable method in the class but acts primarily
        as a helper method to keep the $this.Products variable fresh. Is usually called
        before any setting method that includes logic or is dependent on the state
        of an attribute.
    #>
    [psobject] GetProducts() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/products?after=" -Headers $this.Headers -ErrorAction Stop
            Return $Response
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Get devices data.
        Still exposed as a usable method in the class but acts primarily
        as a helper method to keep the $this.Devices variable fresh. Is usually called
        before any setting method that includes logic or is dependent on the state
        of an attribute.
    #>
    [psobject] GetDevices() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/devices" -Headers $this.Headers -ErrorAction Stop
            Return $Response
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Does what it says on the tin. Returns the currently reported temperature
        value from the thermostat in a single heating zone system.
        Provide $true to get a formatted value: eg. 21.1C
        Provide $false to get a simple decimal: eg. 21.1
    #>
    [psobject] GetTemperature([bool] $FormattedValue) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $this.Products = $this.GetProducts()
            $this.Devices = $this.GetDevices()

            If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }

            $HeatingNode = $this.Products | Where-Object {$_.type -eq "heating"}

            $Temperature = [Math]::Round([double]$HeatingNode.props.temperature, 1)

            If ($FormattedValue) {Return "$($Temperature.ToString())$([char] 176 )C"}
            Else {Return $Temperature}
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Does what it says on the tin. Returns the currently reported temperature
        value from the specified zone.
        Provide $true to get a formatted value: eg. 21.1C
        Provide $false to get a simple decimal: eg. 21.1
    #>
    [psobject] GetTemperature([string] $ZoneName, [bool] $FormattedValue) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $this.Products = $this.GetProducts()
            $this.Devices = $this.GetDevices()

            If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
            
            # Find out the correct node to send the command to. Only the first heating node returned.
            $HeatingNode = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

            $Temperature = [Math]::Round([double]$HeatingNode.props.temperature, 1)

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
        SCHEDULE, MANUAL, OFF. $this.Products and $this.Devices is always refreshed prior to execution.
        This method does not identify the Thermostat on which to set the mode and is suitable only
        single zone heating systems. For multi-zone use the overload and define the zone name as well.
    #>
    [psobject] SetHeatingMode([HeatingMode] $Mode) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        $Settings = [psobject]@{
            mode = $Mode.ToString()
        }
        If ($Mode -eq 'MANUAL') { $Settings.Add('target',20) }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Heating mode set to $($Mode.ToString()) successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Sets the heating mode to one of the [HeatingMode] enum values. ie.
        SCHEDULE, MANUAL, OFF. $this.Products and $this.Devices is always refreshed prior to execution.
        This method identifies the thermostat/programmer to change by the zone name and it does support multi-zones.
    #>
    [psobject] SetHeatingMode([string] $ZoneName, [HeatingMode] $Mode) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the command to by using its name.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        $Settings = [psobject]@{
            mode = $Mode.ToString()
        }
        If ($Mode -eq 'MANUAL') { $Settings.Add('target',20) }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Heating mode set to $($Mode.ToString()) successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Sets the temperature value on the first thermostat device in the system.
        $this.Products and $this.Devices is always refreshed prior to execution.
    #>
    [psobject] SetTemperature([double] $targetTemperature) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Get a sensible temp from the input value rounded to nearest half degree
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        # Check the heating is not in OFF state
        If ($Thermostat.state.mode -eq 'OFF') {
            $this.ReturnError("Heating mode is currently OFF. Set to MANUAL or SCHEDULE first.")
        }

        # This will be converted to JSON. I suppose it could just be JSON but...meh.
        $Settings = [psobject]@{
            target = $Temp
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Desired temperature ($($targetTemperature.ToString())$([char] 176 )C) set successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Sets the temperature value on the first thermostat device in the system.
        $this.Products and $this.Devices is always refreshed prior to execution.
    #>
    [psobject] SetTemperature([string] $ZoneName, [double] $targetTemperature) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Get a sensible temp from the input value rounded to nearest half degree
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
       # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        # Check the heating is not in OFF state
        If ($Thermostat.state.mode -eq 'OFF') {
            $this.ReturnError("Heating mode is currently OFF. Set to MANUAL or SCHEDULE first.")
        }

        # This will be converted to JSON. I suppose it could just be JSON but...meh.
        $Settings = [psobject]@{
            target = $Temp
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
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
        Always boosts to 22C - this is the same as the Hive site.
        Send a SetTemperature() afterward to adjust the Boost up or down.
        You can re-boost at any time but the timer starts again, obviously.
        This boosts only a single zone. For multi-zone systems, use the overload and define the zone name.
    #>
    [psobject] SetBoostMode([BoostTime] $Duration) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

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
            mode = 'BOOST'
            boost = $ApiDuration
            target = $ApiTemperature
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Heating BOOST activated for $ApiDuration minutes at $($ApiTemperature.ToString())$([char] 176 )C"
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Boosts the named heating zone for the defined time.
        The [BoostTime] Enum is used to ensure proper time values are submitted.
        Always boosts to 22C - this is the same as the Hive site.
        Send a SetTemperature() afterward to adjust the Boost up or down.
        You can re-boost at any time but the timer starts again, obviously.
    #>
    [psobject] SetBoostMode([string] $ZoneName, [BoostTime] $Duration) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

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
            mode = 'BOOST'
            boost = $ApiDuration
            target = $ApiTemperature
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Heating BOOST activated for $ApiDuration minutes at $($ApiTemperature.ToString())$([char] 176 )C in $ZoneName"
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        If the current heating mode is set to BOOST, turn it off.
        This reverts the system to its previous configuration using the
        previous value stored for the Thermostat when
        BOOST was activated.
        If BOOST is activated during a schedule that has been overriden,
        canceling boost mode reverts to the scheduled value, not the overriden value.
    #>
    [string] CancelBoostMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        # If the system isn't set to BOOST, return without doing anything.
        If ($Thermostat.state.mode -ne 'BOOST') {
            $this.ReturnError("The current heating mode is not BOOST.")
        }
        
        Switch ($Thermostat.props.previous.mode) {
            SCHEDULE { $this.SetHeatingMode('SCHEDULE') }
            MANUAL {
                $this.SetHeatingMode('MANUAL') 
                $this.SetTemperature($Thermostat.props.previous.target)
            }
            OFF { $this.SetHeatingMode('OFF') }
            Default {$this.SetHeatingMode('SCHEDULE')}
        }

        Return "Heating BOOST cancelled."
    }

    <#
        If the named heating zone mode is set to BOOST, turns it off.
        This reverts the system to its previous configuration using the
        previous value stored for the Thermostat when
        BOOST was activated.
        If BOOST is activated during a schedule that has been overriden,
        canceling boost mode reverts to the scheduled value, not the overriden value.
    #>
    [string] CancelBoostMode([string] $ZoneName) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        # If the system isn't set to BOOST, return without doing anything.
        If ($Thermostat.state.mode -ne 'BOOST') {
            $this.ReturnError("The current heating mode is not BOOST.")
        }
        
        Switch ($Thermostat.props.previous.mode) {
            SCHEDULE { $this.SetHeatingMode('SCHEDULE') }
            MANUAL {
                $this.SetHeatingMode('MANUAL') 
                $this.SetTemperature($Thermostat.props.previous.target)
            }
            OFF { $this.SetHeatingMode('OFF') }
            Default {$this.SetHeatingMode('SCHEDULE')}
        }

        Return "Heating BOOST cancelled in $ZoneName."
    }


    <#
        Get information about current holiday mode settings.
        Returns a string value for start and end dates.
    #>
    [string] GetHolidayMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $Holiday = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/holiday-mode" -Headers $this.Headers -ErrorAction Stop
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }

        # Init variables...
        $Start = $End = $Temp = $null

        If ($Holiday.enabled -eq $true) {
            $Start = [DateTime]::SpecifyKind($this.ConvertUnixTime($Holiday.start), [DateTimeKind]::Local)
            $End = [DateTime]::SpecifyKind($this.ConvertUnixTime($Holiday.end), [DateTimeKind]::Local)
            $Temp = [int] $Holiday.temperature
        }
        ElseIf ($Holiday.enabled -eq $false) {
            Return "Holiday mode is not currently enabled."
        }
        Else {
            $this.ReturnError("Unable to determine the current settings of holiday mode.")
        }

        Return "Holiday mode is enabled from $($Start.ToLocalTime().ToString()) -> $($End.ToLocalTime().ToString()) @ $Temp$([char]176)C."        
    }

    <#
        Enable holiday mode, providing a start date, end date and temperature.
        Ranges are checked that you don't set anything silly and have your heating on 24/7
        while you're away.
    #>
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
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        # The user will only ever define a local time but force it anyway.
        $StartDateUTC = [DateTime]::SpecifyKind($StartDateTime, [DateTimeKind]::Local)
        $EndDateUTC = [DateTime]::SpecifyKind($EndDateTime, [DateTimeKind]::Local)

        $Settings = [psobject]@{
            temperature = $Temperature
            start = $this.DateTimeToUnixTimestamp($StartDateUTC)
            end = $this.DateTimeToUnixTimestamp($EndDateUTC)
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/holiday-mode" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Holiday mode activated from $($StartDateTime.ToString()) -> $($EndDateTime.ToString()) @ $Temperature$([char]176)C."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Cancels holiday mode. Sends the request whether holiday mode is enabled or not.
    #>
    [string] CancelHolidayMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        Try {
            $Response = Invoke-RestMethod -Method Delete -Uri "$($this.ApiUrl)/holiday-mode" -Headers $this.Headers
            Return "Holiday mode cancelled."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Get the current weather (temp, conditions) for the users' postcode location.
    #>
    [psobject] GetWeather() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        $Postcode = $this.User.postcode
        $Country = $this.User.countryCode
        
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "https://weather-prod.bgchprod.info/weather?postcode=$Postcode&country=$Country"
            Return $Response.weather | Select-Object description, temperature
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Get the current weather (temp, conditions) for a specific postcode location.
        Make sure the postcode is accurate or you'll likely get an error. I don't validate it!
    #>
    [psobject] GetWeather([string] $Postcode, [string] $CountryCode) {
        $Postcode = $Postcode.Replace(' ', '').ToUpper()
        $CountryCode = $CountryCode.Replace(' ', '').ToUpper()
        
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "https://weather-prod.bgchprod.info/weather?postcode=$Postcode&country=$CountryCode"
            Return $Response.weather | Select-Object description, temperature
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Get the outside weather temperature for the users' postcode location in C
        Simply uses another method to retrieve the full result and return only the temp.
    #>
    [int] GetWeatherTemperature() {
        Return $this.GetWeather().temperature.value
    }

    <#
        Save your current heating schedule to a JSON formatted file.
        Save different schedules for different times of the year and upload them as required
        using SetHeatingScheduleFromFile().
        Specify a directory ONLY - the file will be named HiveSchedule-yyyyMMddHHmm.json
    #>
    [void] SaveHeatingScheduleToFile([System.IO.DirectoryInfo] $DirectoryPath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not $DirectoryPath.Exists) {$this.ReturnError("The path should already exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        # Create the correct json structure.
        $Settings = [psobject]@{
            schedule = $Thermostat.state.schedule
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

    <#
        Save your named heating zone schedule to a JSON formatted file.
        Save different schedules for different times of the year and upload them as required
        using SetHeatingScheduleFromFile().
        Specify a directory ONLY - the file will be named HiveSchedule-yyyyMMddHHmm.json
    #>
    [void] SaveHeatingScheduleToFile([string] $ZoneName, [System.IO.DirectoryInfo] $DirectoryPath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not $DirectoryPath.Exists) {$this.ReturnError("The path should already exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        # Create the correct json structure.
        $Settings = [psobject]@{
            schedule = $Thermostat.state.schedule
        }

        # Create the file output path and name.
        $File = [System.IO.Path]::Combine($DirectoryPath, "HiveSchedule-$ZoneName-$(Get-Date -Format "yyyyMMdd-HHmm").json")

        # Save the file to disk or error if it exists - let the user handle renaming/moving/deleting.
        Try {
            ConvertTo-Json -InputObject $Settings -Depth 99 | Out-File -FilePath $File -NoClobber
        }
        Catch {
            $this.ReturnError("An error occurred saving the file.`r`n$_")
        }
    }


    <#
        Reads in a JSON file containing heating schedule data, checks it and uploads to the Hive site.
        To ensure that the format is correct, it is recommended to save a copy of your current
        schedule first using SaveHeatingScheduleToFile().
    #>
    [string] SetHeatingScheduleFromFile([System.IO.FileInfo] $FilePath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not (Test-Path -Path $FilePath )) {$this.ReturnError("The file path supplied does not exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        $Settings = $null
        
        # Read in the schedule data from the file.
        Try {
            $Settings = ConvertFrom-Json -InputObject (Get-Content -Path $FilePath -Raw)
        }
        Catch {
            $this.ReturnError("The file specified could not be parsed as valid JSON.`r`n$_")
        }

        # Seven days of events in the file?
        If (((($Settings.schedule).psobject.Members | Where-Object {$_.MemberType -eq 'NoteProperty'}).count) -eq 7) {
            Try {
                $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
                Return "Schedule set successfully from $FilePath"
            }
            Catch {
                $this.ReturnError($_)
                Return $null
            }
        }
        Else {Return "The schedule in the file must contain entries for all seven days."}
    }

    <#
        Set a heating zone schedule from a saved schedule file.
    #>
    [string] SetHeatingScheduleFromFile([string] $ZoneName, [System.IO.FileInfo] $FilePath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not (Test-Path -Path $FilePath )) {$this.ReturnError("The file path supplied does not exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        $Settings = $null
        
        # Read in the schedule data from the file.
        Try {
            $Settings = ConvertFrom-Json -InputObject (Get-Content -Path $FilePath -Raw)
        }
        Catch {
            $this.ReturnError("The file specified could not be parsed as valid JSON.`r`n$_")
        }

        # Seven days of events in the file?
        If (((($Settings.schedule).psobject.Members | Where-Object {$_.MemberType -eq 'NoteProperty'}).count) -eq 7) {
            Try {
                $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/heating/$($Thermostat.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
                Return "Schedule set successfully from $FilePath"
            }
            Catch {
                $this.ReturnError($_)
                Return $null
            }
        }
        Else {Return "The schedule in the file must contain entries for all seven days."}
    }

    <#
        Advance your heating to the next setting based on the current schedule.
        If no time period exists in the current day's schedule, the first event in the next
        day's schedule is used.
    #>
    [string] SetHeatingAdvance() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating"}).Count -is [int]) { $this.ReturnError('There is more than one product of type "heating". Please identify which heating zone by providing the zone name.') }
        
        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating"} | Select-Object -First 1

        # Check the heating is in SCHEDULE mode.
        If (-not ($Thermostat.state.mode -eq 'SCHEDULE')) {
            $this.ReturnError("Heating mode is not currently SCHEDULE. Advancing is not possible.")
        }

        # Get the schedule data
        $Schedule = $Thermostat.state.schedule

        # Get the current date and time.
        $Date = Get-Date
        $MinutesPastMidnight = ($Date - $Date.Date).TotalMinutes

        # Set up variables.
        $NextEvent = $null
        
        # Get today's schedule
        $DaySchedule = Select-Object -InputObject $Schedule -ExpandProperty $Date.DayOfWeek.ToString()

        # Get the next period/schedule from today's events
        Foreach ($Period in $DaySchedule) {
            If (($Period.start) -gt $MinutesPastMidnight) {
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
        Return "Advancing to $($NextEvent.value.target)$([char]176)C...`r`n$($this.SetTemperature($NextEvent.value.target))"
    }

    <#
        Advance the named heating zone to the next slot based on the current schedule.
        If no time period exists in the current day's schedule, the first event in the next
        day's schedule is used.
    #>
    [string] SetHeatingAdvance([string] $ZoneName) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}).Count -is [int]) { $this.ReturnError("No heating zones matching the name provided: `"$ZoneName`" were found.") }
        
        # Find out the correct node to send the commands to.
        $Thermostat = $this.Products | Where-Object {$_.type -eq "heating" -and $_.state.name -eq $ZoneName}

        # Check the heating is in SCHEDULE mode.
        If (-not ($Thermostat.state.mode -eq 'SCHEDULE')) {
            $this.ReturnError("Heating mode is not currently SCHEDULE. Advancing is not possible.")
        }

        # Get the schedule data
        $Schedule = $Thermostat.state.schedule

        # Get the current date and time.
        $Date = Get-Date
        $MinutesPastMidnight = ($Date - $Date.Date).TotalMinutes

        # Set up variables.
        $NextEvent = $null
        
        # Get today's schedule
        $DaySchedule = Select-Object -InputObject $Schedule -ExpandProperty $Date.DayOfWeek.ToString()

        # Get the next period/schedule from today's events
        Foreach ($Period in $DaySchedule) {
            If (($Period.start) -gt $MinutesPastMidnight) {
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
        Return "Advancing to $($NextEvent.value.target)$([char]176)C...`r`n$($this.SetTemperature($NextEvent.value.target))"
    }


    <#
        Get the object data for an Active Plug by its name.
    #>
    hidden [psobject] GetActivePlug([string]$Name) {
        $ActivePlug = $this.Products | Where-Object {($_.type -eq "activeplug") -and ($_.state.name -eq $Name)}
        If ($ActivePlug) { Return $ActivePlug }
        Else { Return $false }
    }

    <#
        Set the mode of an active plug to be either MANUAL or SCHEDULE.
        If you switch to schedule and the plug schedule is to be on, the plug will turn on.
        If you subsequently switch back to MANUAL, the plug will not switch off again
        as there is no previous configuration setting on Active Plugs.
    #>
    [string] SetActivePlugMode([ActivePlugMode]$Mode, [string]$Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }
        
        $Settings = $null

        Switch ($ActivePlug.state.mode) {
           {($_ -eq "MANUAL") -and ($Mode -eq 'MANUAL') } { Return "`"$Name`" is already in MANUAL." }
           {($_ -eq "SCHEDULE") -and ($Mode -eq 'SCHEDULE') } { Return "`"$Name`" is already in SCHEDULE." }
        }

        Switch ($Mode) {
            'MANUAL' { $Settings = [psobject]@{mode = "MANUAL"} }
            'SCHEDULE' { $Settings = [psobject]@{mode = "SCHEDULE"} }
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/activeplug/$($ActivePlug.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
        
        Return "Active Plug `"$Name`" set to $($Settings.mode) successfully."
    }

    <#
        Set the state of a named Active Plug to be either on ($true) or off ($false).
        Uses a boolean as opposed to a text value.
    #>
    [string] SetActivePlugState([bool]$State, [string]$Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }
        
        $Settings = $null

        Switch ($ActivePlug.state.status) {
           {($_ -eq "ON") -and ($State -eq $true) } { Return "`"$Name`" is already ON." }
           {($_ -eq "OFF") -and ($State -eq $false) } { Return "`"$Name`" is already OFF." }
        }

        Switch ($State) {
            $true { $Settings = [psobject]@{status = "ON"} }
            $false { $Settings = [psobject]@{status = "OFF"} }
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/activeplug/$($ActivePlug.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
        
        Return "Active Plug `"$Name`" set to $($Settings.status) successfully."
    }

    <#
        Save an Active Plug schedule to a JSON formatted file.
        Specify a directory ONLY - the file will be named HiveActivePlugSchedule-yyyyMMddHHmm.json
    #>
    [void] SaveActivePlugScheduleToFile([System.IO.DirectoryInfo] $DirectoryPath, [string] $Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not $DirectoryPath.Exists) {$this.ReturnError("The path should already exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()
        
        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }

        # Create the correct json structure.
        $Settings = [psobject]@{
            schedule = $ActivePlug.state.schedule
        }

        # Create the file output path and name.
        $File = [System.IO.Path]::Combine($DirectoryPath, "HiveActivePlugSchedule-$(Get-Date -Format "yyyyMMdd-HHmm").json")

        # Save the file to disk or error if it exists - let the user handle renaming/moving/deleting.
        Try {
            ConvertTo-Json -InputObject $Settings -Depth 99 | Out-File -FilePath $File -NoClobber
        }
        Catch {
            $this.ReturnError("An error occurred saving the file.`r`n$_")
        }
    }

    <#
        Reads in a JSON file containing Active Plug schedule data, checks it and uploads to the Hive site.
        To ensure that the format is correct, it is recommended to save a copy of your current
        schedule first using SaveActivePlugScheduleToFile().
        If you have multiple plugs and want them synchronised, you only have to update one schedule, save it,
        then upload it to all the other plugs identified by name.
    #>
    [string] SetActivePlugScheduleFromFile([System.IO.FileInfo] $FilePath, [string] $Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not (Test-Path -Path $FilePath )) {$this.ReturnError("The file path supplied does not exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }

        $Settings = $null
        
        # Read in the schedule data from the file.
        Try {
            $Settings = ConvertFrom-Json -InputObject (Get-Content -Path $FilePath -Raw)
        }
        Catch {
            $this.ReturnError("The file specified could not be parsed as valid JSON.`r`n$_")
        }

        # Seven days of events in the file?
        If (((($Settings.schedule).psobject.Members | Where-Object {$_.MemberType -eq 'NoteProperty'}).count) -eq 7) {
            Try {
                $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/activeplug/$($ActivePlug.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
                Return "$($ActivePlug.state.name) schedule set successfully from `"$FilePath`""
            }
            Catch {
                $this.ReturnError($_)
                Return $null
            }
        }
        Else {Return "The schedule in the file must contain entries for all seven days."}
    }

    <#
        Get the current power consumption, in watts, of the named Active Plug.
        This is useful for monitoring devices that might run for an indeterminate
        amount of time, such as an auto-sensing clothes dryer. As this value falls to a low number,
        the Active Plug can be turned off.
    #>
    [int] GetActivePlugPowerConsumption([string] $Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()
        
        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }

        # Return the current power consumption.
        Return $ActivePlug.props.powerConsumption    
    }

    <#
        Get Active Plug State - whether it is currently on or off.
    #>
    [bool] GetActivePlugState([string]$Name) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        # Check that the plug name exists and assign to a var if so.
        If (-not ($ActivePlug = $this.GetActivePlug($Name))) {
            $this.ReturnError("The active plug name provided `"$Name`" does not exist.")
        }

        $State = $null

        Switch ($ActivePlug.state.status) {
           {($_ -eq "ON") } { $State = $true }
           {($_ -eq "OFF") } { $State = $false }
           Default { $State = $null }
        }
        Return $State
    }

    <#
        Set the Hot Water mode. Requires one of the following: OFF, MANUAL, SCHEDULE
    #>
    [psobject] SetHotWaterMode([HeatingMode] $Mode) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}

        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "hotwater"}).Count -is [int]) { $this.ReturnError('There is no hot water device attached to this system.') }
        
        # Find out the correct node to send the commands to.
        $HotWater = $this.Products | Where-Object {$_.type -eq "hotwater"} | Select-Object -First 1

        $Settings = [psobject]@{
            mode = $Mode.ToString()
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/hotwater/$($HotWater.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Hot water mode set to $($Mode.ToString()) successfully."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Hot water boost.
    #>
    [psobject] SetHotWaterBoostMode([BoostTime] $Duration) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "hotwater"}).Count -is [int]) { $this.ReturnError('There is no hot water device attached to this system.') }
        
        # Find out the correct node to send the commands to.
        $HotWater = $this.Products | Where-Object {$_.type -eq "hotwater"} | Select-Object -First 1

        $ApiDuration = $null # Creating so it's there!

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
            mode = 'BOOST'
            boost = $ApiDuration
        }

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/hotwater/$($HotWater.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
            Return "Hot water BOOST activated for $ApiDuration minutes."
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Cancel hot water boost.
    #>
    [string] CancelHotWaterBoostMode() {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        
        # Update nodes
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "hotwater"}).Count -is [int]) { $this.ReturnError('There is no hot water device attached to this system.') }
        
        # Find out the correct node to send the commands to.
        $HotWater = $this.Products | Where-Object {$_.type -eq "hotwater"} | Select-Object -First 1

        # If the system isn't set to BOOST, return without doing anything.
        If ($HotWater.state.mode -ne 'BOOST') {
            $this.ReturnError("The current hot water mode is not BOOST.")
        }
        
        Switch ($HotWater.props.previous.mode) {
            SCHEDULE { $this.SetHotWaterMode('SCHEDULE') }
            MANUAL { $this.SetHotWaterMode('MANUAL') }
            OFF { $this.SetHotWaterMode('OFF') }
            Default {$this.SetHotWaterMode('OFF')}
        }

        Return "Hot water BOOST cancelled."
    }

    <#
        Save hot water schedule to a file.
    #>
    [void] SaveHotWaterScheduleToFile([System.IO.DirectoryInfo] $DirectoryPath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not $DirectoryPath.Exists) {$this.ReturnError("The path should already exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "hotwater"}).Count -is [int]) { $this.ReturnError('There is no hot water device attached to this system.') }
        
        # Find out the correct node to send the commands to.
        $HotWater = $this.Products | Where-Object {$_.type -eq "hotwater"} | Select-Object -First 1

        # Create the correct json structure.
        $Settings = [psobject]@{
            schedule = $HotWater.state.schedule
        }

        # Create the file output path and name.
        $File = [System.IO.Path]::Combine($DirectoryPath, "HiveHotWaterSchedule-$(Get-Date -Format "yyyyMMdd-HHmm").json")

        # Save the file to disk or error if it exists - let the user handle renaming/moving/deleting.
        Try {
            ConvertTo-Json -InputObject $Settings -Depth 99 | Out-File -FilePath $File -NoClobber
        }
        Catch {
            $this.ReturnError("An error occurred saving the file.`r`n$_")
        }
    }

    <#
        Reads in a JSON file containing heating schedule data, checks it and uploads to the Hive site.
        To ensure that the format is correct, it is recommended to save a copy of your current
        schedule first using SaveHeatingScheduleToFile().
    #>
    [string] SetHotWaterScheduleFromFile([System.IO.FileInfo] $FilePath) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        If (-not (Test-Path -Path $FilePath )) {$this.ReturnError("The file path supplied does not exist.")}

        # Update nodes data
        $this.Products = $this.GetProducts()
        $this.Devices = $this.GetDevices()

        If (($this.Products | Where-Object {$_.type -eq "hotwater"}).Count -is [int]) { $this.ReturnError('There is no hot water device attached to this system.') }
        
        # Find out the correct node to send the commands to.
        $HotWater = $this.Products | Where-Object {$_.type -eq "hotwater"} | Select-Object -First 1

        $Settings = $null
        
        # Read in the schedule data from the file.
        Try {
            $Settings = ConvertFrom-Json -InputObject (Get-Content -Path $FilePath -Raw)
        }
        Catch {
            $this.ReturnError("The file specified could not be parsed as valid JSON.`r`n$_")
        }

        # Seven days of events in the file?
        If (((($Settings.schedule).psobject.Members | Where-Object {$_.MemberType -eq 'NoteProperty'}).count) -eq 7) {
            Try {
                $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/nodes/hotwater/$($HotWater.id)" -Headers $this.Headers -Body (ConvertTo-Json $Settings -Depth 99 -Compress)
                Return "Schedule set successfully from $FilePath"
            }
            Catch {
                $this.ReturnError($_)
                Return $null
            }
        }
        Else {Return "The schedule in the file must contain entries for all seven days."}
    }

    <#
        Retrieves the status of a named motion sensor.
    #>
    [psobject] GetMotionSensorState([string] $SensorName, [bool] $IncludeTodaysEvents) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $this.Products = $this.GetProducts()
            $this.Devices = $this.GetDevices()

            If (($this.Products | Where-Object {$_.type -eq "motionsensor" -and $_.state.name -eq $SensorName}).Count -is [int]) { $this.ReturnError("No motion sensor matching the name provided: `"$SensorName`" was found.") }
            
            # Find out the correct motion sensor node to obtain the state of.
            $SensorNode = $this.Products | Where-Object {$_.type -eq "motionsensor" -and $_.state.name -eq $SensorName}

            $Response = $null

            If ($IncludeTodaysEvents) {
                # Get the events from today - note this is from "products" not "nodes".
                Try {
                    $TodayStart = Get-Date -Hour 0 -Minute 0 -Second 0
                    $TodayEnd = Get-Date -Hour 23 -Minute 59 -Second 59
                    $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/products/motionsensor/$($SensorNode.id)/events?from=$($this.DateTimeToUnixTimestamp($TodayStart))&to=$($this.DateTimeToUnixTimestamp($TodayEnd))" -Headers $this.Headers
                }
                Catch {
                    $this.ReturnError($_)
                    Return $null
                }

                # Convert the unix timestamps in the response to date time objects so they can be read easily.
                for ($i=0; $i -le ($Response.Count - 1); $i++) {
                    $Response[$i].start = $this.ConvertUnixTime($Response[$i].start)
                    $Response[$i].end = $this.ConvertUnixTime($Response[$i].end)
                }
            }
            If ($IncludeTodaysEvents) {
                $MotionSensor = [ordered]@{
                    Online = $SensorNode.props.online
                    MotionDetected = $SensorNode.props.motion.status
                    StartTime = $this.ConvertUnixTime($SensorNode.props.motion.start)
                    EndTime = $this.ConvertUnixTime($SensorNode.props.motion.end)
                    LatestEvent = $Response | Sort-Object -Descending -Property start | Select-Object -First 1
                    TodaysEvents = $Response
                }
            }
            Else {
                $MotionSensor = [ordered]@{
                    Online = $SensorNode.props.online
                    MotionDetected = $SensorNode.props.motion.status
                    StartTime = $this.ConvertUnixTime($SensorNode.props.motion.start)
                    EndTime = $this.ConvertUnixTime($SensorNode.props.motion.end)
                }
            }

            Return $MotionSensor
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    <#
        Retrieves the status of a named contact (window/door) sensor and its event history.
    #>
    [psobject] GetContactSensorState([string] $SensorName, [bool] $IncludeTodaysEvents) {
        If (-not $this.ApiSessionId) {$this.ReturnError("No ApiSessionId - must log in first.")}
        Try {
            $this.Products = $this.GetProducts()
            $this.Devices = $this.GetDevices()

            If (($this.Products | Where-Object {$_.type -eq "contactsensor" -and $_.state.name -eq $SensorName}).Count -is [int]) { $this.ReturnError("No contact sensor matching the name provided: `"$SensorName`" was found.") }
            
            # Find out the correct contact sensor node to obtain the state of.
            $SensorNode = $this.Products | Where-Object {$_.type -eq "contactsensor" -and $_.state.name -eq $SensorName}

            $Response = $null # Declare variable

            If ($IncludeTodaysEvents) {
                # Get the events from today - this is the first time we're getting the history of something - note this is from "products" not "nodes".
                Try {
                    $TodayStart = Get-Date -Hour 0 -Minute 0 -Second 0
                    $TodayEnd = Get-Date -Hour 23 -Minute 59 -Second 59
                    $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/products/contactsensor/$($SensorNode.id)/events?from=$($this.DateTimeToUnixTimestamp($TodayStart))&to=$($this.DateTimeToUnixTimestamp($TodayEnd))" -Headers $this.Headers
                }
                Catch {
                    $this.ReturnError($_)
                    Return $null
                }

                # Convert the unix timestamps in the response to date time objects so they can be read easily.
                for ($i=0; $i -le ($Response.Count - 1); $i++) {
                    $Response[$i].start = $this.ConvertUnixTime($Response[$i].start)
                    $Response[$i].end = $this.ConvertUnixTime($Response[$i].end)
                }
            }
            If ($IncludeTodaysEvents) {
                $ContactSensor = [ordered]@{
                    SensorStatus = $SensorNode.props.status
                    LatestEvent = $Response | Sort-Object -Descending -Property start | Select-Object -First 1
                    TodaysEvents = $Response
                }
            }
            Else {
                $ContactSensor = [ordered]@{
                    SensorStatus = $SensorNode.props.status
                }
            }

            Return $ContactSensor
        }
        Catch {
            $this.ReturnError($_)
            Return $null
        }
    }

    
# END HIVE CLASS
}    