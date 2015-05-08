<#
.SYNOPSIS  
	Sample for using alfredps.

.PARAMETER importFromSource
    If set this will import from the local source
#>
[cmdletbinding()]
param(
    [string]$installUri='https://raw.githubusercontent.com/sayedihashimi/alfredps/master/getalfred.ps1'
)

function Get-ScriptDirectory{
    split-path $MyInvocation.ScriptName
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$destfolder = (Join-Path $scriptDir 'dest')
$sourcefolder = $scriptDir

if(-not (Get-Module alfred)){
    # see if it's available locally
    if(Test-Path (Join-Path $scriptDir '..\alfred.psm1')){
        Import-Module (Join-Path $scriptDir '..\alfred.psm1') -DisableNameChecking
    }
    else{
        # install from github
        (new-object Net.WebClient).DownloadString($installUri) | iex
    }
}

task init{
    if(-not (Test-Path $destfolder)){
        New-Item -Path $destfolder -ItemType Directory -Force
    }

    Get-ChildItem $destfolder -Recurse -File | Remove-Item

    requires alfred-less
    requires alfred-coffee
    requires alfred-sass
}

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
        minifycss |
        dest "$destfolder\site.min.css"
}

task demominifyjs{
    dir "$sourcefolder\js\jquery-1.10.2.js" |
        src |
        minifyjs |
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

#task runall -dependsOn init,democopy,democoncat,demominifycss,demominifyjs,demominifyjs2,combineandminify,demoless
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



