Enum HeatingMode {
    # Defines the heating modes that can be set.
    OVERRIDE
    SCHEDULE
    MANUAL
    OFF
}

Class Hive {

    [uri]$ApiUrl = "https://api-prod.bgchprod.info/omnia/" # APIv6.1
    [ValidateLength(4,100)][string] $Username
    [ValidateLength(4,100)][string] $Password
    [string] $ApiSessionId
    [string] $Agent = 'PoSHive (Alpha) - lewisroberts.com'
    [psobject] $Nodes
    [hashtable] $Headers = @{
        'Accept' = 'application/vnd.alertme.zoo-6.1+json'
        'X-AlertMe-Client' = 'lewisroberts.com PoSHive 0.1 Alpha'
        'Content-Type' = 'application/json'
    }
    
    # Constructor
    Hive([string] $Username, [string] $Password) {
        $this.Username = $Username
        $this.Password = $Password
    }

    [void] Login () {
        # Construct the username password object that will be converted to JSON.
        # This could really just be JSON but...POWAAAAASHELL.
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

    [psobject] Logout() {
        If (-not $this.ApiSessionId) {Return "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Delete -Uri "$($this.ApiUrl)/auth/sessions/$($this.ApiSessionId)" -Headers $this.Headers
            $this.ApiSessionId = $null
            $this.Headers.Remove('X-Omnia-Access-Token')
            Return "Logged Out Successfully."
        }
        Catch {
            Return $_
        }
    }

    [psobject] GetTemperature() {
        If (-not $this.ApiSessionId) {Return "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/nodes" -Headers $this.Headers
            $this.Nodes = $Response.nodes
            $Temperature = [Math]::Round($Response.nodes.attributes.temperature.reportedValue, 1)
            Return $Temperature
        }
        Catch {
            Return $_
        }
    }

    #<# Only nodes for now.
    [psobject] GetClimate() {
        If (-not $this.ApiSessionId) {Return "No ApiSessionId - must log in first."}
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/nodes" -Headers $this.Headers
            Return $Response
        }
        Catch {
            Return $_
        }
    }
    #>

    <#
    # Needs updating for APIv6
    [psobject] SetHeatingMode([HeatingMode] $Mode) {

        $Settings = @{
            control = $Mode
        }

        Try {
            # Tailored to my own Receiver - yours is different, I'll work on making this
            # dynamic once I get the damned request to work!
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/" -Body (ConvertTo-Json $Settings) -WebSession $this.ApiSessionCookie

            Return $Response
        }
        Catch {
            Return $_
        }
    }
    #>

    [psobject] SetTemperature([double]$targetTemperature) {
        If (-not $this.ApiSessionId) {Return "No ApiSessionId - must log in first."}
        # Get a sensible temp from the input value
        $Temp = ([Math]::Round(($targetTemperature * 2), [System.MidpointRounding]::AwayFromZero)/2)

        # Find out the correct node to send the temp to. Only the first Thermostat we find!
        $Thermostat = $this.Nodes.nodes | Where-Object {$_.attributes.targetHeatTemperature} | Select -First 1

        # Check the submitted temp doesn't exceed the permitted values
        If (($Temp -gt $Thermostat.attributes.maxHeatTemperature.reportedValue) -or ($Temp -lt $Thermostat.attributes.minHeatTemperature.reportedValue)) {
            Return "Submitted temperature value ($Temp) exceeds the permitted range ($($Thermostat.attributes.maxHeatTemperature.reportedValue) - $($Thermostat.attributes.minHeatTemperature.reportedValue))"
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
}

<#
# Instantiate the Hive class with your Hive username (email address) and password.
$h = [Hive]::new('user@domain.com', 'myhivewebsitepassword')

# Log in
$h.Login()

# Get details about the climate in your house
$h.GetClimate()

# Get the current temperature - not very accurate, Thermostat device is better.
$h.GetTemperature()

# Set the temperature (automatically sets heating mode to MANUAL)
$h.SetTemperature(21)

# NOT WORKING
# Change the heating mode to one of Enum [HeatingMode]
$h.SetHeatingMode('OFF')

# Be nice and log out/destroying ApiSession and associated cookie.
$h.Logout()
#>