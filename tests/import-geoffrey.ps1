Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

function Load-AlfredModule{
    [cmdletbinding()]
    param(
        [string]$alfredModulePath = (Join-Path $scriptDir '..\geoffrey.psm1')
    )
    process{
        $env:IsDeveloperMachine = $true
        if(-not (Test-Path $alfredModulePath)){
            throw ('Unable to find alfred at [{0}]' -f $alfredModulePath)
        }
        if(Get-Module alfred){
            Remove-Module alfred -force
        }
        Import-Module $alfredModulePath -Force -DisableNameChecking
    }
}

Load-AlfredModule