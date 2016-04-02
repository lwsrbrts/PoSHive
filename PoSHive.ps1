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
    hidden [string] $Agent = 'PoSHive (Alpha) - github.com/lwsrbrts/PoSHive'
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

    # Login - could do this in the constructor but makes sense to have it as a separate method.
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
        }
        Catch {
            Throw $_.Exception.Response            
        }
    }

    # Log out - essentially deletes the ApiSession from the API and nulls the ApiSessionId
    [psobject] Logout() {
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Delete -Uri "$($this.ApiUrl)/auth/sessions/$($this.ApiSessionId)" -Headers $this.Headers
            # Needs some error checking.
            $this.ApiSessionId = $null
            $this.Headers.Remove('X-Omnia-Access-Token')
            Return "Logged out successfully."
        }
        Catch {
            Throw $_.Exception.Response
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
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/nodes" -Headers $this.Headers -ErrorAction Stop
            Return $Response.nodes
        }
        Catch {
            Throw $_.Exception.Response
        }
    }
    #>

    <#
        Does what it says on the tin. Returns the currently reported temperature
        value from the thermostat. Not likely to work as expected in multi-zone/thermostat
        Hive systems. Sorry.
        Provide $true to get a formatted value: eg. 21.1�C
        Provide $false to get a simple decimal: eg. 21.1
    #>
    [psobject] GetTemperature([bool] $FormattedValue) {
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        Try {
            $this.Nodes = $this.GetClimate()
            $Temperature = [Math]::Round($this.Nodes.attributes.temperature.reportedValue, 1)
            If ($FormattedValue) {Return "$($Temperature.ToString())$([char] 176 )C"}
            Else {Return $Temperature}
        }
        Catch {
            Throw $_.Exception.Response
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
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}

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
            Throw $_.Exception.Response
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
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        
        # Get a sensible temp from the input value rounded to nearest half degree
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Update nodes
        $this.Nodes = $this.GetClimate()

        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        # Check the submitted temp doesn't exceed the permitted values
        If (($Temp -gt $Thermostat.attributes.maxHeatTemperature.reportedValue) -or ($Temp -lt $Thermostat.attributes.minHeatTemperature.reportedValue)) {
            Throw "Submitted temperature value ($Temp) exceeds the permitted range ($($Thermostat.attributes.minHeatTemperature.reportedValue) -> $($Thermostat.attributes.maxHeatTemperature.reportedValue))"
        }

        # Check the heating is not in OFF state
        If ($Thermostat.attributes.activeHeatCoolMode.reportedValue -eq 'OFF') {
            Throw "Heating mode is currently OFF. Set to MANUAL or SCHEDULE first."
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
            Throw $_.Exception.Response
        }
    }

    <#
        Boosts the heating system for the defined time.
        The [BoostTime] Enum is used to ensure proper time values are submitted.
        Always boosts to 22�C - this is the same as the Hive site.
        To cancel boosting:

        $Hive.SetHeatingMode([HeatingMode] $Value)
        ---AND---
        $Hive.SetTemperature([double] $Value)

        or allow the timer to run out.
        You can re-boost at any time but the timer starts again, obviously.
        ENHANCEMENT: There is a "previousConfiguration" value that I will likely
        implement in to a .CancelBoostMode() method.
    #>
    [psobject] SetBoostMode([BoostTime] $Duration) {
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        
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
            Throw $_.Exception.Response
        }
    }

# END HIVE CLASS
}