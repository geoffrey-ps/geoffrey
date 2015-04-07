# Alfred - the PowerShell task runner for web

### Initial concept

```powershell
$alfred = (new-object Net.WebClient).DownloadString("http://alfredps.com/getalfred.ps1") | iex

requires alfred-less
requires alfred-coffee
requires alfred-concat

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