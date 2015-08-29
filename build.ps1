[cmdletbinding(DefaultParameterSetName='build')]
param(
    [Parameter(ParameterSetName='build',Position=0)]
    [switch]$build,

    [Parameter(ParameterSetName='build',Position=1)]
    [switch]$cleanBeforeBuild,

    [Parameter(ParameterSetName='clean',Position=0)]
    [switch]$clean
)

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
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

function Build-Projects{
    [cmdletbinding()]
    param()
    process {
        $projectToBuild = Join-Path $scriptDir 'vs\AlfredTrx\AlfredTrx.sln'

        if(-not (Test-Path $projectToBuild)){
            throw ('Could not find the project to build at [{0}]' -f $projectToBuild)
        }

        Invoke-MSBuild $projectToBuild -visualStudioVersion 14.0 -configuration Release -properties @{'DeployExtension'='false'}

    }
}

function Clean{
    [cmdletbinding()]
    param()
    process {
        [System.IO.FileInfo]$projectToBuild = Join-Path $scriptDir 'vs\AlfredTrx\AlfredTrx.sln'

        if(-not (Test-Path $projectToBuild)){
            throw ('Could not find the project to build at [{0}]' -f $projectToBuild)
        }

        Invoke-MSBuild $projectToBuild -visualStudioVersion 14.0 -targets Clean -properties @{'DeployExtension'='false'}

        [System.IO.DirectoryInfo[]]$foldersToDelete = (Join-Path $scriptDir 'vs\AlfredTrx\AlfredTrx\bin\'),(Join-Path $scriptDir 'vs\AlfredTrx\AlfredTrx\obj\')
        foreach($folder in $foldersToDelete){
            if(Test-Path $folder){
                Remove-Item $folder -Recurse
            }
        }
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

if(-not $clean -and (-not $build)){
    $build = $true
}

if($clean){
    Clean
}

if($build){
    Build-Projects
    Run-Tests
}
