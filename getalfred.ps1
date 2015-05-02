[cmdletbinding()]
param(
    [string]$sourceUri = 'https://raw.githubusercontent.com/sayedihashimi/alfredps/master/alfred.psm1',
    [string]$toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools\")
)

$installFolder = (Join-Path $toolsDir 'alfredps-pre')
$installPath = (Join-Path $installFolder 'alfred.psm1')

# for now we re-install each time so delete the folder if it exists
if(Test-Path $installPath){
    Remove-Item $installPath
}
if(-not (Test-Path $installFolder)){
    new-item -Path $installFolder -ItemType Directory
}
'Downloading alfred.psm1 from [{0}] to [{1}]' -f $sourceUri,$installPath | Write-Verbose
(New-Object System.Net.WebClient).DownloadFile($sourceUri, $installPath) | Out-Null

# if the module is imported then remove it
if(Get-Module alfred){
    'Removing alfred module' | Write-Verbose
    Remove-Module alfred -force
}

'Importing alfred module from [{0}]' -f $installPath | Write-Verbose
Import-Module $installPath -DisableNameChecking -Global
