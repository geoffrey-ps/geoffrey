# geoffrey - the PowerShell task runner for web

![geoffrey logo](resources/geoffrey-face.png)

[![Build status](https://ci.appveyor.com/api/projects/status/67if3jcubral0wfh?svg=true)](https://ci.appveyor.com/project/sayedihashimi/geoffrey)

### Initial concept

```powershell
$geoffrey = (new-object Net.WebClient).DownloadString("http://getgeoffrey.com/getgeoffrey.ps1") | iex

requires geoffrey-less
requires geoffrey-coffee
requires geoffrey-concat

task copy {
    src './less/site.less' |         # gets site.less (i think it would return Stream based objects but not sure)
      less './less/site.less' |      # converts from site.less to site.css (?where is the temp file stored? or is all streams)
      dest './css'                   # writes the file to the ./css/site.css
}
task coffee {
    src './coffee/*.coffee','./lib/coffee/*.coffee' |
      concat 'site.js' |
      coffee |
      dest './'
}

task default -depends copy,less,coffee
```
