# geoffrey - the PowerShell task runner for web

![geoffrey logo](resources/geoffrey-face.png)

[![Build status](https://ci.appveyor.com/api/projects/status/67if3jcubral0wfh?svg=true)](https://ci.appveyor.com/project/sayedihashimi/geoffrey)

#### download and install geoffrey
<code style="background-color:grey">(new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/geoffrey-ps/geoffrey/master/getgeoffrey.ps1") | iex</code>


### initial concept

```powershell
task init{
    if(-not (Test-Path $destfolder)){
        New-Item -Path $destfolder -ItemType Directory -Force
    }

    Get-ChildItem $destfolder -Recurse -File | Remove-Item

    requires geoffrey-less
    requires geoffrey-coffee
    requires geoffrey-sass
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

```
