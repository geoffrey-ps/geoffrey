Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

function Load-GeoffreyModule{
    [cmdletbinding()]
    param(
        [string]$geoffreyModulePath = (Join-Path $scriptDir '..\geoffrey.psm1')
    )
    process{
        if(-not (Test-Path $geoffreyModulePath)){
            throw ('Unable to find geoffrey at [{0}]' -f $geoffreyModulePath)
        }
        if(Get-Module geoffrey){
            Remove-Module geoffrey -force
        }
        Import-Module $geoffreyModulePath -Force -DisableNameChecking
    }
}

Load-GeoffreyModule