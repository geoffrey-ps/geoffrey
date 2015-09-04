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

    [Parameter(ParameterSetName='build',Position=4)]
    [switch]$publishToNuget,

    [Parameter(ParameterSetName='build',Position=5)]
    [string]$nugetApiKey = ($env:NuGetApiKey),

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

[System.IO.DirectoryInfo]$outputPathNuget = (Join-Path $outputPath '_nuget-pkg')

function EnsurePsbuildInstlled{
    [cmdletbinding()]
    param(
        [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/master/src/GetPSBuild.ps1'
    )
    process{
        if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
            'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($psbuildInstallUri) | iex
        }
        else{
            'psbuild already loaded, skipping download' | Write-Verbose
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
            throw ('Unable to install/load psbuild from [{0}]' -f $psbuildInstallUri)
        }
    }
}

function EnsureNuGetPowerShellInstlled{
    [cmdletbinding()]
    param(
        [string]$installUri = 'https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1'
    )
    process{
        if(-not (Get-Command -Name Get-NuGetPackage -Module nuget-powershell -errorAction SilentlyContinue)){
            'Installing nuget-powershell from [{0}]' -f $installUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($installUri) | iex
        }
        else{
            'nuget-powershell already loaded, skipping download' | Write-Verbose
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Name Get-NuGetPackage -Module nuget-powershell -errorAction SilentlyContinue)){
            throw ('Unable to install/load nuget-powershell from [{0}]' -f $installUri)
        }
    }
}

function Initalize{
    [cmdletbinding()]
    param()
    process{
        EnsurePsbuildInstlled
        EnsureNuGetPowerShellInstlled
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

        # copy other files to the output folder
        [System.IO.FileInfo[]]$filesToCopy = "$scriptDir\geoffrey.nuspec","$scriptDir\geoffrey.psm1","$scriptDir\LICENSE","$scriptDir\readme.md"
        Copy-Item -Path $filesToCopy -Destination $outputPath        
    }
}

function Build-NuGetPackage{
    [cmdletbinding()]
    param()
    process{
        if(-not (Test-Path $outputPathNuget)){
            New-Item -Path $outputPathNuget -ItemType Directory
        }

        Push-Location
        try{
            Set-Location $outputPath
            'building nuget package' | Write-Output
            Invoke-CommandString -command (Get-Nuget) -commandArgs @('pack','geoffrey.nuspec','-NoPackageAnalysis','-OutputDirectory',($outputPathNuget.FullName))
        }
        finally{
            Pop-Location
        }
    }
}

function PublishNuGetPackage{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$nugetPackages,

        [Parameter(Mandatory=$true)]
        $nugetApiKey
    )
    process{
        foreach($nugetPackage in $nugetPackages){
            $pkgPath = (get-item $nugetPackage).FullName
            $cmdArgs = @('push',$pkgPath,$nugetApiKey,'-NonInteractive')

            'Publishing nuget package with the following args: [nuget.exe {0}]' -f ($cmdArgs -join ' ') | Write-Verbose
            &(Get-Nuget) $cmdArgs
        }
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

if($publishToNuget){
    $clean = $true
}

if($clean){
    Clean
}

if($build){
    Build-Projects
    Run-Tests
    Build-NuGetPackage

    # publish to nuget if selected
    if($publishToNuget){
        (Get-ChildItem -Path ($outputPathNuget) 'geoffrey*.nupkg').FullName | PublishNuGetPackage -nugetApiKey $nugetApiKey
    }
}
