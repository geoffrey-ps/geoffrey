[cmdletbinding()]
param(
    [string]$sourceUri = 'https://raw.githubusercontent.com/geoffrey-ps/geoffrey/master/getgeoffrey.ps1',
    [string]$toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools\")
)

$installFolder = (Join-Path $toolsDir 'geoffrey-pre')
$installPath = (Join-Path $installFolder 'geoffrey.psm1')

function EnsureNuGetPowerShellInstlled{
    [cmdletbinding()]
    param(
        [string]$installUri = 'https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1'
    )
    process{
        if(-not (Get-Command -Name Get-NuGetPackage -Module nuget-powershell -errorAction SilentlyContinue)){
            'Installing nuget-powershell from [{0}]' -f $installUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($installUri) | iex
        }
        else{
            'nuget-powershell already loaded, skipping download' | Write-Verbose
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Name Get-NuGetPackage -Module nuget-powershell -errorAction SilentlyContinue)){
            throw ('Unable to install/load nuget-powershell from [{0}]' -f $installUri)
        }
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

# install script

try{
    # get the module locally
    $installpath = (Get-NuGetPackage -name geoffrey -version 0.0.2-beta -binpath)

    # if the module is imported then remove it
    if(Get-Module geoffrey){
        'Removing geoffrey module' | Write-Verbose
        Remove-Module geoffrey -force
    }

    # copy the files to the powershell modules folder
    $destFolderPath = (Join-Path (GetPsModulesPath) 'geoffrey')
    if(-not (Test-Path $destFolderPath)){
        'Creating modules folder at [{0}]' -f $destFolderPath | Write-Verbose
        New-Item -Path $destFolderPath -ItemType Directory
    }

    [System.IO.FileInfo[]]$filesToCopy = (Get-ChildItem -Path $installPath  *.ps*1)
    $filesToCopy += (Get-ChildItem $installPath *.dll)
    $filesToCopy += (Get-ChildItem $installPath *.md)
    'Copying files to modules folder at [{0}]' -f $destFolderPath | Write-Verbose
    $filesToCopy | Copy-Item -Destination $destFolderPath

    Import-Module -Name (Join-Path $destFolderPath 'geoffrey.psm1')
}
catch{
    'There was an error installing geoffrey. Exception details: {0}' -f ($_.Exception) | Write-Error
}


<#
# for now we re-install each time so delete the folder if it exists
if(Test-Path $installPath){
    Remove-Item $installPath
}
if(-not (Test-Path $installFolder)){
    new-item -Path $installFolder -ItemType Directory
}
'Downloading geoffrey.psm1 from [{0}] to [{1}]' -f $sourceUri,$installPath | Write-Verbose
(New-Object System.Net.WebClient).DownloadFile($sourceUri, $installPath) | Out-Null

# if the module is imported then remove it
if(Get-Module geoffrey){
    'Removing geoffrey module' | Write-Verbose
    Remove-Module geoffrey -force
}

'Importing geoffrey module from [{0}]' -f $installPath | Write-Verbose
Import-Module $installPath -DisableNameChecking -Global
#>