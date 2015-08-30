[cmdletbinding()]
param(
    [string]$sourceUri = 'https://raw.githubusercontent.com/sayedihashimi/geoffrey/master/geoffrey.psm1',
    [string]$toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools\")
)

$installFolder = (Join-Path $toolsDir 'geoffrey-pre')
$installPath = (Join-Path $installFolder 'geoffrey.psm1')

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
