function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$buildScriptPath = (Join-Path $scriptDir 'build.ps1')

. $buildScriptPath -notests