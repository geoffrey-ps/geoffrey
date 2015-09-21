<#
.SYNOPSIS  
	Sample for using geoffrey.

.PARAMETER importFromSource
    If set this will import from the local source
#>
[cmdletbinding()]
param(
    [string]$installUri='https://raw.githubusercontent.com/geoffrey-ps/geoffrey/master/getgeoffrey.ps1'
)

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$destfolder = (Join-Path $scriptDir 'dest')
$sourcefolder = $scriptDir

if(-not (Get-Module geoffrey)){
    # see if it's available locally
    if(Test-Path (Join-Path $scriptDir '..\geoffrey.psm1')){
        Import-Module (Join-Path $scriptDir '..\geoffrey.psm1') -DisableNameChecking
    }
    else{
        # install from github
        (new-object Net.WebClient).DownloadString($installUri) | iex
    }
}

# todo: figure out a way to avoid this
Reset-Geoffrey
task init{
    if(-not (Test-Path $destfolder)){
        New-Item -Path $destfolder -ItemType Directory -Force
    }

    Get-ChildItem $destfolder -Recurse -File | Remove-Item

    requires ajax-min
    # requires geoffrey-less
    # requires geoffrey-coffee
    # requires geoffrey-sass
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
        cssmin -CommentMode 'None' |
        dest "$destfolder\site.min.css"
}

task demojsmin{
    dir "$sourcefolder\js\jquery-1.10.2.js" |
        src |
        jsmin -settingsJson '{ "PreserveImportantComments":false}' -AlwaysEscapeNonAscii $true -StripDebugStatements $true -MinifyCode $false -AmdSupport $true |
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

geoffreyrun default

