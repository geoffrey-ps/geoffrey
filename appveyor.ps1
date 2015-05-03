$env:ExitOnPesterFail = $true
$env:IsDeveloperMachine=$true

# disabling coverage for now, its not working on appveyor for some reason
#$env:PesterEnableCodeCoverage = $true

.\build.ps1