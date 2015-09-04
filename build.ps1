[cmdletbinding(DefaultParameterSetName='build')]
param(
    [Parameter(ParameterSetName='build',Position=0)]
    [switch]$build,

    [Parameter(ParameterSetName='build',Position=1)]
    [string]$configuration = 'Release',

    [Parameter(ParameterSetName='build',Position=2)]
    [System.IO.DirectoryInfo]$outputPath,

    [Parameter(ParameterSetName='build',Position=3)]
    [switch]$cleanBeforeBuild,


    [Parameter(ParameterSetName='clean',Position=0)]
    [switch]$clean
)

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

if([string]::IsNullOrWhiteSpace($outputPath)){
    $outputPath = (Join-Path $scriptDir 'OutputRoot')
}

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

[hashtable]$buildProperties = @{
    'Configuration'=$configuration
    'DeployExtension'='false'
    'OutputPath'=$outputPath.FullName
    'VisualStudioVersion'='14.0'
}

function Build-Projects{
    [cmdletbinding()]
    param()
    process {
        if($outputPath -eq $null){throw 'outputpath is null'}

        $projectToBuild = Join-Path $scriptDir 'src\Geoffrey.sln'

        if(-not (Test-Path $projectToBuild)){
            throw ('Could not find the project to build at [{0}]' -f $projectToBuild)
        }

        if(-not (Test-Path $OutputPath)){
            'Creating output folder [{0}]' -f $outputPath | Write-Output
            New-Item -Path $outputPath -ItemType Directory
        }

        Invoke-MSBuild $projectToBuild -properties $buildProperties
    }
}

function Clean{
    [cmdletbinding()]
    param()
    process {
        [System.IO.FileInfo]$projectToBuild = Join-Path $scriptDir 'src\Geoffrey.sln'

        if(-not (Test-Path $projectToBuild)){
            throw ('Could not find the project to build at [{0}]' -f $projectToBuild)
        }

        Invoke-MSBuild $projectToBuild -targets Clean -properties $buildProperties

        [System.IO.DirectoryInfo[]]$foldersToDelete = (Get-ChildItem $scriptDir -Include bin,obj -Recurse -Directory)
        $foldersToDelete += $outputPath

        foreach($folder in $foldersToDelete){
            if(Test-Path $folder){
                Remove-Item $folder -Recurse -Force
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
                $pesterArgs.Add('-CodeCoverage','..\geoffrey.psm1')
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
