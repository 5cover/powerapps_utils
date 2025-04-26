#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Description courte de ton script.

.DESCRIPTION
    Explication plus détaillée si nécessaire.

.PARAMETER inputFile
    The filename of the JSON file containing the tokens, declarations, properties.

.PARAMETER property
    The property to generator the formula for. If not provided, formulas are generated for all propeties

.EXAMPLE
    .\sanity.ps1 fluid.json -property Fill
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$inputFile,
    [Parameter(Mandatory = $false)]
    [string]$property
)

$ErrorActionPreference = 'Stop'

if ($inputFile) {
    # Lire depuis fichier
    $jsonContent = Get-Content -Raw -Path $inputFile
} else {
    # Lire depuis stdin
    if ($Input) {
        $jsonContent = $Input | Out-String
    } else {
        Write-Error 'No input provided.'
        exit 1
    }
}

# Parser le JSON
$component = $jsonContent | ConvertFrom-Json

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
        return "If($(($this.Conditions.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            ($_.Value | ForEach-Object {
                $component.name+'.'+$key+'="'+$_+'"'
            }) -join '||'
        }) -join '&&');$($this.Then);$($this.Else))"
    }
}

function Get-Formula {
    param(
        [string]$property
    )

    $branch = $null;

    foreach ($decl in $component.properties.$property) {
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

        $branch = [Branch]::new($conditions, $decl.value, $branch);  
    }

    <#
    If(Emphasis='a' or Emphasis='b'; value; else)
    #>

    Write-Output $branch.ToString()

    <#
    Fill:
    Switch(Emphasis;
        "subtle"; $white;
        "minimal"; $white;
        $main_color)
    #>

}

function Get-Switch {
    param(
        [string]$switchee,
        [hashtable]$cases,
        [string]$default
    )
    if ($cases.Count -eq 0) { return $default }
    return ("Switch($switchee;" + ($cases.GetEnumerator() | ForEach-Object { '"' + $_.Key + '";' + $_.Value + ';' }) + "$default)")

}

Get-Formula -property Fill
