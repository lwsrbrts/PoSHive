#
# Module manifest for module 'PoSHive'
#
# Generated by: Lewis Roberts
#
# Generated on: 24/04/2016
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'PoSHive.ps1'

# Version number of this module.
ModuleVersion = '2.5.0'

# ID used to uniquely identify this module
GUID = 'f8e66ed6-c6c7-4040-908c-6ddeda52c2a0'

# Author of this module
Author = 'Lewis Roberts'

# Company or vendor of this module
# CompanyName = 'Unknown'

# Copyright statement for this module
Copyright = '(c) 2018 Lewis Roberts. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Control your British Gas Hive system (heating, multi-zone heating, hot water, active plugs, sensors, bulbs, partner (Philips Hue) bulbs) and get temperature history as data or charts using PowerShell.'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @()

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @("hive", "heating", "british-gas", "hivehome", "thermostat", "multi-zone", "hot-water", "active-plug", "sensor", "class")

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/lwsrbrts/PoSHive'

        # A URL to an icon representing this module.
        IconUri = 'https://www.lewisroberts.com/wp-content/uploads/2017/06/PoShive-icon2-1.png'

        # ReleaseNotes of this module
        ReleaseNotes = 'This item is a class only. There are methods in the class that you can use to control your heating, hot water, active plugs and sensors but there are no cmdlets so Get-Command will reveal nothing. Please see the project site for more information on how to use the class.'

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

