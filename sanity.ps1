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
    [Parameter(ValueFromPipeline=$true)]
    [string]$Component,
    [Parameter(Mandatory=$false)]
    [string]$Property
)

$ErrorActionPreference = 'Stop'

$global:designSystem = Get-Content -Raw -Path $DesignSystem | ConvertFrom-Json
$global:component = Get-Content -Raw -Path $Component | ConvertFrom-Json

class Branch {
    [hashtable]$Conditions # Map<string, any[]>
    $Then # probably string or Branch
    $Else # probably string or Branch

    Branch([hashtable]$conditions, $then, $else) {
        $this.Conditions = $conditions
        $this.Then = $then
        $this.Else = $else
        if ($this.Conditions.Count -eq 0 -xor $null -eq $else) {
            throw "inconsistent state"
        }
    }

    [string]ToString() {
        if ($null -eq $this.Else) { return $this.Then.ToString(); }
        $condition = ($this.Conditions.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            $cond = ($_.Value | ForEach-Object {
                "$($global:component.name).$key=""$($_)"""
            }) -join '||'
            if ($this.Conditions.Count -gt 1 -and $_.Value.Count -gt 1) {
                "($cond)"
            } else {
                $cond
            }
        }) -join '&&'
        return "If($condition;$($this.Then);$($this.Else))"
    }
}

function ConvertTo-PowerAppsRGBA {
    param(
        [Parameter(Mandatory=$true)]
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
    param (
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

function ConvertTo-Formula {
    param(
        [PSCustomObject[]]$Decls
    )

    $branch = $null;

    foreach ($decl in $Decls) {
        $conditions=@{}
        foreach ($prop in $decl.PSObject.Properties) {
            if ($prop.Name -eq 'value') {
                continue
            }
            $values = $prop.Value;
            if (-not ($values -is [array])) {
                $values = @($values)
            }
            $conditions.($prop.Name) = $values;
        }

        $branch = [Branch]::new($conditions, (ConvertTo-ParsedValue -value $decl.value), $branch);  
    }

    <#
    If(Emphasis='a' or Emphasis='b'; value; else)
    #>

    return $branch.ToString()

    <#
    Fill:
    Switch(Emphasis;
        "subtle"; $white;
        "minimal"; $white;
        $main_color)
    #>

}

function ConvertTo-Switch {
    param(
        [string]$switchee,
        [hashtable]$cases,
        [string]$default
    )
    if ($cases.Count -eq 0) { return $default }
    return ("Switch($switchee;" + ($cases.GetEnumerator() | ForEach-Object { '"' + $_.Key + '";' + $_.Value + ';' }) + "$default)")

}

function ConvertFrom-Property {
    param (
        $Name,
        $Value
    )
    Write-Output "$($Name) ="
    if ($Value -isnot [Object[]]) {
        $Value = [PSCustomObject]@{
            value = $Value
        }
    }
    ConvertTo-Formula -Decls $Value | Write-Output
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

