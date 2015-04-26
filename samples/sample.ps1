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
Import-Module (Join-Path $scriptDir '..\alfred.psm1')

$destfolder = (Join-Path $scriptDir 'dest')
$sourcefolder = $scriptDir

if(-not (Test-Path $destfolder)){
    New-Item -Path $destfolder -ItemType Directory -Force
}

Get-ChildItem $destfolder -Recurse -File | Remove-Item

requires alfred-less
requires alfred-coffee
requires alfred-sass

task democopy {
    src "$sourcefolder\css\site.css" |
        dest "$destfolder\site-from-ps.css"
}

task democoncat {
    dir "$sourcefolder\css\lib *.css" |
        src | 
        concat "$destfolder\combined.css"
}

task demominifycss{
    # todo: figure out how handle dest given a folder instead of file paths
    dir "$sourcefolder\css\site.css" |
        src |
        minifycss |
        dest "$destfolder\site.min.css"
}

task demominifyjs{
    # todo: figure out how handle dest given a folder instead of file paths
    dir "$sourcefolder\js\jquery-1.10.2.js" |
        src |
        minifycss |
        dest "$destfolder\jquery-1.10.2.min.js"
}

alfredrun democopy
alfredrun democoncat
alfredrun demominifycss
alfredrun demominifyjs