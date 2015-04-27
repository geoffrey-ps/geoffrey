[cmdletbinding()]
param()

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

if(Get-Module alfred){
    Remove-Module alfred -force
}
Import-Module (Join-Path $scriptDir '..\alfred.psm1') -Force

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
    dir "$sourcefolder\css\lib\*.css" |
        src | 
        dest "$destfolder\combined.css"
}

task demominifycss{
    dir "$sourcefolder\css\site.css" |
        src |
        minifyjs |
        dest "$destfolder\site.min.css"
}

task demominifyjs{
    dir "$sourcefolder\js\jquery-1.10.2.js" |
        src |
        minifycss |
        dest "$destfolder\jquery-1.10.2.min.js"
}

task demominifyjs2{
    $dest = (Join-Path $destfolder 'demominifyjs2')
    if(-not (Test-Path $dest)){
        New-Item -ItemType Directory -Path $dest | out-null
    }
    dir "$sourcefolder\js\jquery-1.10.2.js","$sourcefolder\js\r.js" |
        src |
        minifyjs |
        dest "$dest"
}

task combineandminify{
    dir "$sourcefolder\js\jquery-1.10.2.js","$sourcefolder\js\r.js" |
        src |
        minifyjs |
        dest "$destfolder\combineminify.js"
}

task demoless{
    dir "$sourcefolder\less\basic.less" |
        src |
        less |
        dest "$destfolder\basic-from-less.css"

    dir "$sourcefolder\less\site.less" |
        src |
        less |
        dest "$destfolder\site-from-less.css"
}

task runall -dependsOn democopy,democoncat,demominifycss,demominifyjs,demominifyjs2,combineandminify,demoless

<#
alfredrun democopy
alfredrun democoncat
alfredrun demominifycss
alfredrun demominifyjs
alfredrun demominifyjs2
alfredrun combineandminify
#>

# this will run all the tasks
alfredrun runall



