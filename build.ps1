[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path $MyInvocation.ScriptName
}
$scriptDir = ((Get-ScriptDirectory) + "\")

<#
.SYNOPSIS
    Will make sure that psbuild is installed and loaded. If not it will
    be downloaded.
#>
function EnsurePsbuildInstlled{
    [cmdletbinding()]
    param(
        [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/master/src/GetPSBuild.ps1'
    )
    process{
        # if psbuild is not available
        if(-Not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue) -or (-not ((Get-Command "Import-Pester" -errorAction SilentlyContinue)))){
            'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($psbuildInstallUri) | iex
        }
        else{
            'psbuild already loaded' | Write-Verbose
        }
    }
}

function Initalize{
    [cmdletbinding()]
    param()
    process{
        EnsurePsbuildInstlled
        # load pester
        Import-Pester
    }
}

function Run-Tests{
    [cmdletbinding()]
    param()
    process{
        try{
            Push-Location
            Set-Location (Join-Path $scriptDir 'tests')
            
            $pesterArgs = @{
                '-PassThru' = $true
            }
            if($env:ExitOnPesterFail -eq $true){
                $pesterArgs.Add('-EnableExit',$true)
            }
            if($env:PesterEnableCodeCoverage -eq $true){
                $pesterArgs.Add('-CodeCoverage','..\alfred.psm1')
            }

            $pesterResult = Invoke-Pester @pesterArgs
            if($pesterResult.FailedCount -gt 0){
                throw ('Failed test cases: {0}' -f $pesterResult.FailedCount)
            }
        }
        finally{
            Pop-Location
        }
    }
}

# being script
Initalize
Run-Tests




