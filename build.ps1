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

    [Parameter(ParameterSetName='build',Position=6)]
    [switch]$notests,

    # version parameters
    [Parameter(ParameterSetName='setversion',Position=0)]
    [switch]$setversion,

    [Parameter(ParameterSetName='setversion',Position=1,Mandatory=$true)]
    [string]$newversion,

    [Parameter(ParameterSetName='getversion',Position=0)]
    [switch]$getversion,

    # clean parameters
    [Parameter(ParameterSetName='clean',Position=0)]
    [switch]$clean,

    [Parameter(ParameterSetName='openciwebsite',Position=0)]
    [Alias('openci')]
    [switch]$openciwebsite
)

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

if([string]::IsNullOrWhiteSpace($outputPath)){
    $outputPath = (Join-Path $scriptDir 'OutputRoot')
}

$env:GeoffreyBinPath = $outputPath

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

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Name Get-NuGetPackage -Module nuget-powershell -errorAction SilentlyContinue)){
            throw ('Unable to install/load nuget-powershell from [{0}]' -f $installUri)
        }
    }
}

function EnsureFileReplacerInstlled{
    [cmdletbinding()]
    param()
    begin{
        EnsureNuGetPowerShellInstlled
    }
    process{
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            $fpinstallpath = (Get-NuGetPackage -name file-replacer -version '0.4.0-beta' -binpath)
            if(-not (Test-Path $fpinstallpath)){ throw ('file-replacer folder not found at [{0}]' -f $fpinstallpath) }
            Import-Module (Join-Path $fpinstallpath 'file-replacer.psm1') -DisableNameChecking
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            throw ('Unable to install/load file-replacer')
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
        $env:IsDeveloperMachine=$true
        if($outputPath -eq $null){throw 'outputpath is null'}

        $projectToBuild = Join-Path $scriptDir 'projects\Geoffrey.sln'

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
        [System.IO.FileInfo]$projectToBuild = Join-Path $scriptDir 'projects\Geoffrey.sln'

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

# TODO: Figure out a way to run the tests in a new powershell session
#       so that the watch assembly can be unloaded

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

function Update-FilesWithCommitId{
    [cmdletbinding()]
    param(
        [string]$commitId = ($env:APPVEYOR_REPO_COMMIT),

        [Parameter(Position=2)]
        [string]$filereplacerVersion = '0.4.0-beta'
    )
    begin{
        EnsureFileReplacerInstlled
    }
    process{
        if(![string]::IsNullOrWhiteSpace($commitId)){
            'Updating commitId from [{0}] to [{1}]' -f '$(COMMIT_ID)',$commitId | Write-Verbose

            $folder = $scriptDir
            $include = '*.nuspec'
            # In case the script is in the same folder as the files you are replacing add it to the exclude list
            $exclude = "$($MyInvocation.MyCommand.Name);"
            $replacements = @{
                '$(COMMIT_ID)'="$commitId"
            }
            Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose
            'Replacement complete' | Write-Verbose
        }
    }
}

<#
.SYNOPSIS 
This will inspect the publsish nuspec file and return the value for the Version element.
#>
function GetExistingVersion{
    [cmdletbinding()]
    param(
        [ValidateScript({test-path $_ -PathType Leaf})]
        $nuspecFile = (Join-Path $scriptDir 'geoffrey.nuspec')
    )
    process{
        ([xml](Get-Content $nuspecFile)).package.metadata.version
    }
}

function SetVersion{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$newversion,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$oldversion = (GetExistingVersion),

        [Parameter(Position=2)]
        [string]$filereplacerVersion = '0.4.0-beta'
    )
    begin{
        EnsureFileReplacerInstlled
    }
    process{
        $folder = $scriptDir
        $include = '*.nuspec;*.ps*1'
        # In case the script is in the same folder as the files you are replacing add it to the exclude list
        $exclude = "$($MyInvocation.MyCommand.Name);"
        $exclude += ';build.ps1'
        $replacements = @{
            "$oldversion"="$newversion"
        }
        Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose

        # update the .psd1 file if there is one
        $replacements = @{
            ($oldversion.Replace('-beta','.1'))=($newversion.Replace('-beta','.1'))
        }
        Replace-TextInFolder -folder $folder -include '*.psd1' -exclude $exclude -replacements $replacements | Write-Verbose
        'Replacement complete' | Write-Verbose
    }
}

function OpenCiWebsite{
    [cmdletbinding()]
    param()
    process{
        start 'https://ci.appveyor.com/project/sayedihashimi/geoffrey'
    }
}

function Build-All{
    [cmdletbinding()]
    param()
    process{
        Update-FilesWithCommitId
        Build-Projects
        if(-not $notests){
            Run-Tests
        }
        else{
            $importscriptpath = (Join-Path $scriptDir 'tests\import-geoffrey.ps1')
            . $importscriptpath
        }
        Build-NuGetPackage

        # publish to nuget if selected
        if($publishToNuget){
            (Get-ChildItem -Path ($outputPathNuget) 'geoffrey*.nupkg').FullName | PublishNuGetPackage -nugetApiKey $nugetApiKey
        }
    }
}

# being script
Initalize

if(!$build -and !$setversion -and !$getversion -and !$openciwebsite){
    $build = $true
}

try{
    if($build){ Build-All }
    elseif($setversion){ SetVersion -newversion $newversion }
    elseif($getversion){ GetExistingVersion | Write-Output }
    elseif($openciwebsite){ OpenCiWebsite }
    else{
        $cmds = @('-build','-setversion','-getversion','-openciwebsite')
        'Command not found or empty, please pass in one of the following [{0}]' -f ($cmds -join ' ') | Write-Error
    }
}
catch{
    "Build failed with an exception:`n{0}" -f ($_.Exception.Message) |  Write-Error
    exit 1
}
