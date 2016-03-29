Enum HeatingMode {
    # Defines the heating modes that can be set.
    OVERRIDE
    SCHEDULE
    MANUAL
    OFF
}

Class Hive {

    #[uri]$ApiUrl = "https://api.prod.bgchprod.info/api" - doesn't work (SSL cert issue?) - maybe it can be overridden?
    [uri]$ApiUrl = "https://api.bgchlivehome.co.uk/v5"
    [ValidateLength(4,100)][string] $Username
    [ValidateLength(4,100)][string] $Password
    [string] $ApiSession
    [string] $Agent = 'PoSHive (Alpha) - lewisroberts.com'
    [string[]] $hubIds
    $ApiSessionCookie
    
    # Constructor
    Hive([string] $Username, [string] $Password) {
        $this.Username = $Username
        $this.Password = $Password
        $this.ApiSessionCookie = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    }

    [void] Login () {
        $Settings = @{}
        $Settings.Add("username", $this.Username)
        $Settings.Add("password", $this.Password)
        $Settings.Add("caller", $this.Agent)

        Try {
            $Response = Invoke-RestMethod -Method Post -Uri "$($this.ApiUrl)/login" -Body $Settings -ErrorAction Stop
            $this.ApiSession = $Response.ApiSession
            $this.hubIds = $Response.hubIds

            $Cookie = New-Object System.Net.Cookie 
    
            $Cookie.Name = "ApiSession"
            $Cookie.Value = $this.ApiSession
            $Cookie.Domain = $this.ApiUrl.Host
            
            $this.ApiSessionCookie.Cookies.Add($Cookie)
        }
        Catch {
            Write-Error $_            
        }
    }

    [psobject] Logout() {
        Try {
            $Response = Invoke-WebRequest -Method Post -Uri "$($this.ApiUrl)/logout" -WebSession $this.ApiSessionCookie
            If ($Response.StatusCode -ne 204) {
                Write-Output "The log out request was not performed."
                Return $Response
            }
            Else {
                $this.ApiSession = $null
                Return "Logged Out Successfully."
            }
        }
        Catch {
            Return $_
        }
    }

    [psobject] GetTemperature() {
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/users/$($this.Username)/widgets/temperature" -WebSession $this.ApiSessionCookie
            Return $Response
        }
        Catch {
            Return $_
        }
    }

    #<#
    [psobject] GetClimate() {
        Try {
            $Response = Invoke-RestMethod -Method Get -Uri "$($this.ApiUrl)/users/$($this.Username)/widgets/climate" -WebSession $this.ApiSessionCookie
            Return $Response
        }
        Catch {
            Return $_
        }
    }
    #>

    #<#
    # Not working yet, but we're close.
    [psobject] SetHeatingMode([HeatingMode] $Mode) {

        $Settings = @{
            control = $Mode
        }

        Try {
            # Tailored to my own Receiver - yours is different, I'll work on making this
            # dynamic once I get the damned request to work!
            $Response = Invoke-RestMethod -Method Put -Uri "$($this.ApiUrl)/users/$($this.Username)/widgets/climate/[Thermostat deviceID]/control" -Body (ConvertTo-Json $Settings) -WebSession $this.ApiSessionCookie

            Return $Response
        }
        Catch {
            Return $_
        }
    }
    #>

    [psobject] SetTemperature([int]$targetTemperature) {

        $Settings = @{}
        $Settings.Add("temperature", $targetTemperature)
        $Settings.Add("temperatureUnit", "C")

        Try {
            $Response = Invoke-WebRequest -Method Post -Uri "$($this.ApiUrl)/users/$($this.Username)/widgets/climate/targetTemperature" -Body $Settings -WebSession $this.ApiSessionCookie
            If ($Response.StatusCode -ne 204) {
                Write-Output "The request to set temperature was not performed."
                Return $Response
            }
            Else {
                Return "Desired temperature ($($targetTemperature.ToString())$([char] 176 )C) set successfully."
            }
        }
        Catch {
            Return $_
        }
    }
}

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