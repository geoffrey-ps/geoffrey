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

function GetPsModulesPath{
    [cmdletbinding()]
    param()
    process{
        $Destination = $null
        if(Test-Path 'Env:PSModulePath'){
            $ModulePaths = @($Env:PSModulePath -split ';')

            $ExpectedUserModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowerShell\Modules
            $Destination = $ModulePaths | Where-Object { $_ -eq $ExpectedUserModulePath}
            if (-not $Destination) {
                $Destination = $ModulePaths | Select-Object -Index 0
            }
        }
        $Destination
    }
}

function Remove-GlobalGeoffreyModule{
    [cmdletbinding()]
    param()
    process{
        $modsfolder = GetPsModulesPath
        if(-not [string]::IsNullOrEmpty($modsfolder)){
            [System.IO.FileInfo]$globalmodsinstallpath = (Join-Path $modsfolder 'geoffrey')
            if(Test-Path $globalmodsinstallpath){
                Remove-Item $globalmodsinstallpath -Recurse
            }
        }
    }
}

Remove-GlobalGeoffreyModule
Load-GeoffreyModule