<#
.SYNOPSIS  
	Sample for using alfredps.

.PARAMETER importFromSource
    If set this will import from the local source
#>
[cmdletbinding()]
param()

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$destfolder = (Join-Path $scriptDir 'dest')
$sourcefolder = $scriptDir


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

task democssmin{
    dir "$sourcefolder\css\site.css" |
        src |
        cssmin |
        dest "$destfolder\site.min.css"
}

task demojsmin{
    dir "$sourcefolder\js\jquery-1.10.2.js" |
        src |
        jsmin |
        dest "$destfolder\jquery-1.10.2.min.js"
}

task demojsmin2{
    $dest = (Join-Path $destfolder 'demominifyjs2')
    if(-not (Test-Path $dest)){
        New-Item -ItemType Directory -Path $dest | out-null
    }
    dir "$sourcefolder\js\jquery-1.10.2.js","$sourcefolder\js\r.js" |
        src |
        jsmin |
        dest "$dest"
}

task combineandminify{
    dir "$sourcefolder\js\jquery-1.10.2.js","$sourcefolder\js\r.js" |
        src |
        jsmin |
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

task default -dependsOn democopy,democoncat,democssmin,demojsmin,demojsmin2,combineandminify,demoless
