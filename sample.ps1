[cmdletbinding()]
param()

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

if(Get-Module alfredps){
    Remove-Module alfredps
}
Import-Module (Join-Path $scriptDir 'alfred.psm1')

$destfolder = 'C:\temp\alfredps\dest'

if(-not (Test-Path $destfolder)){
    New-Item -Path $destfolder -ItemType Directory -Force
}

Get-ChildItem $destfolder -Recurse -File | Remove-Item

requires alfred-less
requires alfred-coffee
requires alfred-sass

task democopy {
    src C:\temp\alfredps\css\site.css |
        dest C:\temp\alfredps\dest\site-from-ps.css
}

task democoncat {
    dir C:\temp\alfredps\css\lib *.css |
        src | 
        concat C:\temp\alfredps\dest\combined.css
}

task demominifycss{
    # todo: figure out how handle dest given a folder instead of file paths
    dir C:\temp\alfredps\css\site.css |
        src |
        minifycss |
        dest C:\temp\alfredps\dest\site.min.css
}

alfredrun democopy
alfredrun democoncat
alfredrun demominifycss