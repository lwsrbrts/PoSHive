Enum HeatingMode {
    <# Defines the heating modes that can be set.
    # Boost should be a separate function as it sets different values
    # to the heating mode.
    #>
    SCHEDULE
    MANUAL
    OFF
}

Class Hive {

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
    
    # Constructor
    Hive([string] $Username, [string] $Password) {
        $this.Username = $Username
        $this.Password = $Password
    }

    # Login - could do this in the constructor but makes sense to have it as a separate trapable action.
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
            Write-Error $_            
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
            Return $_
        }
    }

    <#
        Get nodes (devices) data
        Still exposed as a usable method in the class but acts primarily
        as a helper method to keep the $this.Nodes variable fresh. Is usually called
        before any setting method that includes logic or is dependent on the state
        of an attribute.
    #>
    [psobject] GetClimate() {
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/nodes" -Headers $this.Headers
            Return $Response.nodes
        }
        Catch {
            Return $_
        }
    }
    #>

    <#
        Does what it says on the tin. Returns the currently reported temperature
        value from the thermostat. Not likely to work as expected in multi-zone/thermostat
        Hive systems. Sorry.
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
            Return $_
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
            Return $_
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
    [psobject] SetTemperature([double]$targetTemperature) {
        If (-not $this.ApiSessionId) {Throw "No ApiSessionId - must log in first."}
        
        # Get a sensible temp from the input value
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Update nodes
        $this.Nodes = $this.GetClimate()

        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        # Check the submitted temp doesn't exceed the permitted values
        If (($Temp -gt $Thermostat.attributes.maxHeatTemperature.reportedValue) -or ($Temp -lt $Thermostat.attributes.minHeatTemperature.reportedValue)) {
            Throw "Submitted temperature value ($Temp) exceeds the permitted range ($($Thermostat.attributes.maxHeatTemperature.reportedValue) -> $($Thermostat.attributes.minHeatTemperature.reportedValue))"
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
            Return $_
        }
    }

    <#
        Boosts the heating system. NOT IMPLEMENTED YET.
        May need to know the previous system state prior to boosting?
        Is there an accepted boost temperature? Is that derived from the current
        temperature or the target temperature?
        How does it act if the heating mode is OFF?
        Time in minutes is a parameter to this method.
        Will need to refresh nodes and get current temp perhaps.
    #>
    [psobject] HeatBoost() {
        Throw "Not implemented yet."
    }

# END HIVE CLASS
}



<#
# Instantiate the Hive class with your Hive username (email address) and password.
$h = [Hive]::new('user@domain.com', 'myhivewebsitepassword')

# Log in
$h.Login()

# Get details about nodes making up the system (Receiver, Hub, Thermostats)
$h.GetClimate()

## Get the current temperature
# .GetTemperature($true) gives a formatted value (with symbol and letter) to one decimal place.
# .GetTemperature($false) gives simply a number to one decimal place.
$h.GetTemperature($true)

# Set the temperature (automatically sets heating mode to MANUAL)
$h.SetTemperature(21)

# Change the heating mode to one of Enum [HeatingMode]
$h.SetHeatingMode('OFF')
$h.SetHeatingMode('MANUAL')
$h.SetHeatingMode('SCHEDULE')

# Be nice and log out/destroying ApiSession and associated cookie.
$h.Logout()
#>