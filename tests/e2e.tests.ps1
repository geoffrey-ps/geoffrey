[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path $MyInvocation.ScriptName
}
$scriptDir = ((Get-ScriptDirectory) + "\")

. (Join-Path $scriptDir 'import-alfred.ps1')

Describe 'sample.ps1 tests'{
    It 'can run the sample ps1 file with out errors'{
        $sample01path = (Join-Path $scriptDir '..\samples\sample.ps1')
        & $sample01path | Out-Null
    }
}