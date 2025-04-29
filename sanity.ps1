#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate PowerApps formulas for a UI component based on design system tokens.

.DESCRIPTION
    Reads a design system JSON file (design tokens) and a component JSON file (component definitions),
    then builds PowerApps formulas representing all state combinations of the specified component properties.
    This tool simplifies importing design token logic into PowerApps.

.PARAMETER DesignSystem
    Path to the JSON file defining the design system (colors, spacing, fonts).

.PARAMETER Component
    Path to the JSON file defining the component (name, modifiers, properties).

.PARAMETER Property
    (Optional) Name of a single property to generate. If omitted, formulas are generated for all properties.

.EXAMPLE
    # Generate formulas for all properties
    .\\sanity.ps1 .\\fluid.json .\\button.json

.EXAMPLE
    # Generate formula for the Fill property only
    .\\sanity.ps1 .\\designSystem.json .\\component.json -Property Fill

.NOTES
    Requires PowerShell Core 7.x or later.
    Ensure JSON files conform to their respective schemas.
#>


[CmdletBinding()]
param(
    [Parameter()]
    [string]$DesignSystem,
    [Parameter(ValueFromPipeline)]
    [string]$Component,
    [Parameter(Mandatory=$false)]
    [string]$Property
)

$ErrorActionPreference = 'Stop'

$global:designSystem = Get-Content -Raw -Path $DesignSystem | ConvertFrom-Json
$global:component = Get-Content -Raw -Path $Component | ConvertFrom-Json

function ConvertTo-PowerAppsRGBA {
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidatePattern('^#(?:[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$')]
        [string]$HexColor,

        [Parameter(Mandatory=$false)]
        [Nullable[int]]$OpacityPercentage
    )

    # Remove leading '#'
    $hex = $HexColor.TrimStart('#')

    # Extract RGB values
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)

    # Default alpha value
    $a = 1

    if ($hex.Length -eq 8) {
        # If RGBA provided, use provided alpha byte unless opacity is specified
        $alphaByte = [Convert]::ToInt32($hex.Substring(6,2),16)
        $a = $alphaByte / 255
    }

    if ($null -eq $OpacityPercentage) {
        $OpacityPercentage = 100
    }
    # use current culture
    return "RGBA($r;$g;$b;$(($a * ($OpacityPercentage / 100)).ToString()))"
}

function ConvertTo-ParsedValue {
    [OutputType([string])]
    param (
        [Parameter(ValueFromPipeline)]
        [string]$value
    )

    if ($value -match '^\$([\w/-]+)(.*)$') {
        $varName = $Matches.1;
        if (-not ($global:designSystem.tokens | Get-Member $varName)){
            Write-Error "missing variable '$varName'"
            exit 1
        }
        $value = $global:designSystem.tokens.$varName + $Matches.2
    }
    if ($value -match '^(#[A-Fa-f0-9]{6}(?:[A-Fa-f0-9]{2})?)(?:\.([0-9]*\.?[0-9]+))?') {
        $value = ConvertTo-PowerAppsRGBA -HexColor $Matches.1 -OpacityPercentage $Matches.2
    }
    return $value
}

function ConvertTo-Switch {
    [OutputType([string])]
    param(
        [string]$switchee,
        [hashtable]$cases,
        [string]$default
    )
    if ($cases.Count -eq 0) { return $default }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("Switch($switchee;")

    $cases.GetEnumerator() | ForEach-Object {
        [void]$sb.Append("""$($_.Key)"";$($_.Value);")
    }

    [void]$sb.Append("$default)")
    return $sb.ToString()
}


function ConvertTo-Formula {
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$Decls,
        [int]$Level = 0
    )

    $switchee = $global:component.modifiers[$Level]
    if ($null -eq $switchee) {
        Write-Error "too much nesting: $Level"
        exit 1
    }

    $cases = @{}
    $default = $null;

    foreach ($decl in $Decls.PSObject.Properties) {
        $value = $decl.Value;
        if ($value -is [PSCustomObject]) {
            $value = $value | ConvertTo-Formula -Level ($Level + 1)
        } else {
            $value = $value | ConvertTo-ParsedValue
        }

        if ($decl.Name -eq '*') {
            $default = $value;
        } else {
            $cases[$decl.Name] = $value
        }
    }

    return ConvertTo-Switch -switchee "$($global:component.name).$switchee" -cases $cases -default $default
}

function ConvertFrom-Property {
    [OutputType([void])]
    param (
        $Name,
        $Value
    )
    Write-Output "$($Name) ="
    if ($Value -isnot [PSCustomObject]) {
        $Value = [PSCustomObject]@{
            '*' = $Value
        }
    }
    $Value | ConvertTo-Formula | Write-Output
}

if ($Property) {
    if (-not ($global:component.properties | Get-Member $Property)){
        Write-Error "missing property '$Property'"
        exit 1
    }
    ConvertFrom-Property -Name $Property -Value $global:component.properties.$Property
} else {
    foreach ($prop in $global:component.properties.PSObject.Properties) {
        ConvertFrom-Property -Name $prop.Name -Value $prop.Value
    }
}

