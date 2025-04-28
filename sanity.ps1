#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build PowerApps formulas to represent state combinations.

.DESCRIPTION
    todo

.PARAMETER designSystemFile
    The filename of the JSON file representing the design system. Contains design tokens.

.PARAMETER componentFile
    The filename of the JSON file representing the component to build formulas for. Contains the declarations and properties.

.PARAMETER property
    The property to generator the formula for. If not provided, formulas are generated for all propeties

.EXAMPLE
    .\sanity.ps1 fluid.json -property Fill
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$designSystemFile,
    [Parameter(Position=1, ValueFromPipeline=$true)]
    [string]$componentFile,
    [Parameter(Mandatory=$false)]
    [string]$property
)

$ErrorActionPreference = 'Stop'

$global:designSystem = Get-Content -Raw -Path $designSystemFile | ConvertFrom-Json
$global:component = Get-Content -Raw -Path $componentFile | ConvertFrom-Json

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
        $a = [math]::Round($alphaByte / 255, 2)
    }

    if ($null -ne $OpacityPercentage) {
        # Override alpha if opacity percentage is provided
        $a = [math]::Round(($OpacityPercentage / 100), 2)
    }

    return "RGBA($r, $g, $b, $a)"
}

function ConvertTo-ParsedValue {
    param (
        [string]$value
    )

    if ($value -match '^\$(\w+)(.*)$') {
        $value = $global:designSystem.tokens.($Matches.1) + $Matches.2
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

foreach ($prop in $global:component.properties.PSObject.Properties) {
    Write-Output "$($prop.Name) ="
    $value = $prop.Value;
    if ($value -is [string]) {
        $value = [PSCustomObject]@{
            value = $value
        }
    }
    ConvertTo-Formula -Decls $value | Write-Output
}
