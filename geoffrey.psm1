[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((InternalGet-ScriptDirectory) + "\")

$global:geoffreysettings = new-object psobject -Property @{
    NuGetPowerShellMinModuleVersion = '0.2.3.1'
    PrintTaskExecutionTimes = $true
    GeoffreyPrintTasknameColor = 'Yellow'
    GeoffreyPrintTaskTimeColor = 'Green'
    EnableRequiresViaUrl = $true
    EnableLoadingLocalModules = $true
    ModuleSearchPaths = [System.IO.DirectoryInfo[]]@()
    ModulesFolderName = 'gmodules'
}

[bool]$watcherLoaded = $false

if(Test-Path env:geoffreyprinttasktimes){
    $global:geoffreysettings.PrintTaskExecutionTimes =($env:geoffreyprinttasktimes)
}
$global:geoffreycontext = New-Object PSObject -Property @{
    HasBeenInitalized = $false
    Tasks = [hashtable]@{}
    RunTasks = $true
    HasRunInitTask = $false
    TasksExecuted = New-Object System.Collections.Generic.List[System.String]
}

function InternalOverrideSettingsFromEnv{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $settingsObj = $global:geoffreysettings,

        [Parameter(Position=1)]
        [string]$prefix = 'geoffrey'
    )
    process{
        if($settingsObj -eq $null){
            return
        }

        $settingNames = ($settingsObj | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
        foreach($name in $settingNames){
            $fullname = ('{0}{1}' -f $prefix,$name)
            if(Test-Path "env:$fullname"){
                $settingsObj.$name = ((get-childitem "env:$fullname").Value)
            }
        }
    }
}
# call it to override settings now
InternalOverrideSettingsFromEnv

# later we will use this to check if it has been initalized and throw an error if not
function Reset-Geoffrey{
    [cmdletbinding()]
    param()
    process{
        InternalOverrideSettingsFromEnv

        $global:geoffreycontext.Tasks = [hashtable]@{}
        $global:geoffreycontext.RunTasks = $true
        $global:geoffreycontext.HasBeenInitalized = $true
        $global:geoffreycontext.TasksExecuted.Clear()
        $global:geoffreycontext.HasRunInitTask = $false
        Ensure-NuGetPowerShellIsLoaded
    }
}

function Ensure-NuGetPowerShellIsLoaded{
    [cmdletbinding()]
    param(
        $nugetPsMinModVersion = $global:geoffreysettings.NuGetPowerShellMinModuleVersion
    )
    process{
        # see if nuget-powershell is available and load if not
        $nugetpsloaded = $false
        if((get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            # check the module to ensure we have the correct version
            $currentversion = (Get-Module -Name nuget-powershell).Version
            if( ($currentversion -ne $null) -and ($currentversion.CompareTo([version]::Parse($nugetPsMinModVersion)) -ge 0 )){
                $nugetpsloaded = $true
            }
        }

        if(!$nugetpsloaded){
            (new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1") | Invoke-Expression
        }

        # verify it was loaded
        if(-not (get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            throw ('Unable to load nuget-powershell, unknown error')
        }
    }
}

function InternalDownloadAndInvoke{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string]$url
    )
    process{
        [Uri]$uriresult = $null
        [Uri]::TryCreate($url,[UriKind]::Absolute,[ref] $uriresult)
        if($uriresult -ne $null){
            (new-object Net.WebClient).DownloadString(($uriresult.AbsoluteUri)) | Invoke-Expression
        }
        else{
            throw ('Unable to parse the provided url [{0}]' -f $url)
        }
    }
}

function Invoke-GeoffreyRequires{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$nameorurl,

        [Parameter(Position=1)]
        [bool]$condition = $true,

        [Parameter(Position=2)]
        [string]$version,

        [Parameter(Position=3)]
        [switch]$prerelease,

        [Parameter(Position=4)]
        [switch]$noprefix
    )
    begin{
        # make sure nuget-powershell is loaded and ready to be called
        Ensure-NuGetPowerShellIsLoaded
    }
    process{
        if($condition -eq $false){
            'Skipping requires because the condition evaluated to false' | Write-Verbose
            return
        }
        if($global:geoffreycontext.RunTasks -eq $false){
            'Skipping requires because ''geoffreycontext.RunTasks'' is false' | Write-Verbose
            return
        }

        [string]$url = $null
        # see if the value is a url or the name of a nuget package
        [System.Uri]$uriresult = $null
        [Uri]::TryCreate($nameorurl,[UriKind]::Absolute,[ref] $uriresult)
        if($uriresult -ne $null){
            $url = $nameorurl
        }

        # if $url is empty then its a nuget package
        if([string]::IsNullOrWhiteSpace($url)){
            $pkgName = "geoffrey-$nameorurl"
            if($noprefix){
                $pkgName = $nameorurl
            }

            if($global:geoffreysettings.EnableLoadingLocalModules -eq $true){
                $localModuleFound = $false
                # before getting from nuget see if there is a package locally
                [System.IO.DirectoryInfo[]]$searchFolders = (Join-Path $pwd "$($Global:geoffreysettings.ModulesFolderName)\$pkgName"),(Join-Path $scriptDir "$($Global:geoffreysettings.ModulesFolderName)\$pkgName")
                if($geoffreysettings.ModuleSearchPaths -ne $null -and ($geoffreysettings.ModuleSearchPaths.Count -gt 0)){
                    foreach($path in $geoffreysettings.ModuleSearchPaths){
                        $searchFolders += $path
                    }
                }

                foreach($path in $searchFolders){
                    if(Test-Path $path){
                        'Loading module from local folder [{0}]' -f $path | Write-Verbose
                        InternalImport-ModuleFromFolder -path $path -toolsFolderRelPath ''
                        $localModuleFound = $true
                        break;
                    }
                }
            }

            if(-not $localModuleFound){
                # add required params here
                $getnugetparams = @{
                    'name'=$pkgName
                    'binpath'=$true
                }

                if($PSBoundParameters.ContainsKey('version')){
                    $getnugetparams.Add('version',$version)
                }
                if($PSBoundParameters.ContainsKey('prerelease')){
                    $getnugetparams.Add('prerelease',1)
                }

                $pkgpath = Get-NuGetPackage @getnugetparams
                # load the module inside the packages
                InternalImport-ModuleFromFolder -path $pkgpath
            }
        }
        else{
            # invoke with iex
            if( ($global:geoffreysettings.EnableRequiresViaUrl) -eq $true){
                InternalDownloadAndInvoke -url $url
            }
            else{
                'Skipping [requires {0}] because [$global:geoffreysettings.EnableRequiresViaUrl] is false' -f $url | Write-Warning
            }
        }
    }
}
Set-Alias requires Invoke-GeoffreyRequires

<#
.SYNOPSIS
    This will load the module from the folder specified.
    Order to search:
     1. tools\g.install.ps1
     2. tools\*.psd1 - if any file matches *.psd1 then all *.psm1 files are ignored
     3. tools\*.psm1
#>
function InternalImport-ModuleFromFolder{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [System.IO.DirectoryInfo[]]$path,

        [Parameter(Position=1)]
        [string]$toolsFolderRelPath = 'tools'
    )
    process{
        foreach($p in $path){
            try{
                [System.IO.DirectoryInfo]$modFolder = $p
                if(-not [string]::IsNullOrWhiteSpace($toolsFolderRelPath)){
                    $modFolder = (Join-Path $p $toolsFolderRelPath)
                }

                [System.IO.FileInfo]$installFile = (Join-Path $modFolder 'g.install.ps1' -ErrorAction SilentlyContinue)
                [System.IO.FileInfo[]]$psd1Files = (Get-ChildItem $modFolder *.psd1 -ErrorAction SilentlyContinue)
                [System.IO.FileInfo[]]$psm1Files = (Get-ChildItem $modFolder *.psm1 -ErrorAction SilentlyContinue)

                if(Test-Path $installFile){
                    # install file found, execute it
                    'Executing install file at [{0}]' -f ($installFile.FullName) | Write-Verbose
                    . ($installFile.FullName) | Out-Null
                }
                elseif( ($psd1Files -ne $null) -and ($psd1Files.Length -gt 0) ){
                    foreach($psd1 in $psd1Files){
                        'Importing module at [{0}]' -f ($psd1.FullName) | Write-Verbose
                        Import-Module ($psd1.FullName) -Global -DisableNameChecking | Write-Verbose
                    }
                }
                elseif( ($psm1Files -ne $null) -and ($psm1Files.Length -gt 0) ){
                    foreach($psm1 in $psm1Files){
                        'Importing module at [{0}]' -f ($psm1.FullName) | Write-Verbose
                        Import-Module ($psm1.FullName) -Global -DisableNameChecking | Write-Verbose
                    }
                }
                else{
                    'No modules found in [{0}] to import' -f ($p.FullName) | Write-Warning
                }
            }
            catch{
                "An error occured while loading modules in folder [{0}].`r`nException [{1}].`r`n{2}" -f $p, ($_.Exception),(Get-PSCallStack) | Write-Warning
            }
        }
    }
}

<#
.SYNOPSIS
    This is the command that users will use to run scripts.

.PARAMETER scriptPath
    Path to the script to execute, the default is '.\gfile.ps1'

.PARAMETER list
    This will return the list of tasks in the file

.PARAMETER list
    Name(s) of the task(s) that should be executed. This will accept either a single
    value or multiple values.
#>
function Invoke-Geoffrey{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo]$scriptPath = '.\gfile.ps1',

        [Parameter(Position=1)]
        [switch]$list,

        [Parameter(Position=2)]
        [string[]]$taskName
    )
    begin{
        Reset-Geoffrey
    }
    process{
        $taskNamePassed = ($PSBoundParameters.ContainsKey('taskName'))
        $runtasks = !($list -or $taskName)

        try{
            $global:geoffreycontext.RunTasks =$runtasks
            # execute the script
            . $scriptPath

            if($list){
                # output the name of all the registered tasks
                $global:geoffreycontext.Tasks.Keys
            }
            elseif($taskNamePassed){ # if -list is passed don't execute anything
                $runtaskpreviousvalue = $global:geoffreycontext.RunTasks
                try{
                    $global:geoffreycontext.RunTasks = $true
                    Invoke-GeoffreyTask $taskName
                }
                finally{
                    $global:geoffreycontext.RunTasks = $runtaskpreviousvalue
                }
            }
            else{
                # execute the default task if it exists
                $defaultTask = $global:geoffreycontext.Tasks.Item('default')
                if( $defaultTask -ne $null ){
                    Invoke-GeoffreyTask -name default
                }
            }
        }
        finally{
            $global:geoffreycontext.RunTasks = $true
        }
    }
}
Set-Alias geoffrey Invoke-Geoffrey

<#
.SYNOPSIS
This will create a new task, register it with geoffrey and return the object itself. If there is already
a task with the given name it will be overwritten
#>
function New-GeoffreyTask{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,

        [Parameter(Position=1)]
        [ScriptBlock]$defintion,

        [Parameter(Position=2)]
        [string[]]$dependsOn
    )
    begin{
        if($global:geoffreycontext.HasBeenInitalized -ne $true){
            Reset-Geoffrey
        }
    }
    process{
        $result = New-Object psobject -Property @{
            Name = $name
            Definition = $defintion
            DependsOn = $dependsOn
        }
        $global:geoffreycontext.Tasks[$name]=$result
    }
}
set-alias task New-GeoffreyTask

function Invoke-GeoffreyTask{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$name,

        [switch]
        $force
    )
    process{
        if( ($global:geoffreycontext.RunTasks -eq $true) -or $force){
            # run the init task if not already
            if($global:geoffreycontext.HasRunInitTask -ne $true){
                # set this before calling the task to ensure the if only passes once
                $global:geoffreycontext.HasRunInitTask = $true

                $initTask = $global:geoffreycontext.Tasks.Item('init')
                if( $initTask -ne $null -and ([string]::Compare($name,'init') -ne 0) ){
                    Invoke-GeoffreyTask -name init
                }
            }

            foreach($taskname in $name){
                [System.Diagnostics.Stopwatch]$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                # skip executing the task if already executed
                if( ($global:geoffreycontext.TasksExecuted.Contains($taskname)) -and (-not $force) ){
                    'Skipping task [{0}] because it has already been executed' -f $taskname | Write-Verbose
                    continue;
                }

                if(-not $global:geoffreycontext.TasksExecuted.Contains($taskname)){
                    $global:geoffreycontext.TasksExecuted.Add($taskname)
                }                

                $tasktorun = $global:geoffreycontext.Tasks[$taskname]

                if($tasktorun -eq $null){
                    throw ('Did not find a task with the name [{0}]' -f $taskname)
                }

                if($tasktorun.DependsOn -ne $null){
                    foreach($dtask in ($tasktorun.DependsOn)){
                        # avoid infinite loop
                        if([string]::Compare($taskname,$dtask) -ne 0){
                            Invoke-GeoffreyTask $dtask
                        }
                    }
                }

                if($tasktorun.Definition -ne $null){
                    'Invoking task [{0}]' -f $taskname | Write-Verbose
                    & (($global:geoffreycontext.Tasks[$taskname]).Definition)
                }

                $stopwatch.Stop()
                Write-TaskExecutionInfo -taskname $taskname -milliseconds $stopwatch.ElapsedMilliseconds
            }
        }
    }
}
Set-Alias geoffreyrun Invoke-GeoffreyTask

function Write-TaskExecutionInfo{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$taskname,
        [Parameter(Position=1)]
        $milliseconds
    )
    process{
        if($global:geoffreysettings.PrintTaskExecutionTimes -eq $true){
            $usewriteobj = $true

            if(get-command Write-Host -ErrorAction SilentlyContinue){
                try{
                    '{0}:' -f $taskname | Write-Host -NoNewline -ForegroundColor $global:geoffreysettings.GeoffreyPrintTasknameColor -ErrorAction SilentlyContinue
                    ' {0}' -f $milliseconds | Write-Host -ForegroundColor $global:geoffreysettings.GeoffreyPrintTaskTimeColor -NoNewline -ErrorAction SilentlyContinue
                    ' milliseconds' | Write-Host -ErrorAction SilentlyContinue

                    # if it gets here there was no error calling Write-Host
                    $usewriteobj = $false
                }
                catch{
                    # ignore and use write-object below
                }
            }

            if($usewriteobj){
                '{0}: {1} milliseconds' -f $taskname,$milliseconds | Write-Output
            }
        }
    }
}

function InternalGet-GeoffreyPipelineObject{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$streamObjects
    )
    end{
        if($streamObjects -ne $null){
            $pipelineObj = New-Object -TypeName psobject -Property @{
                StreamObjects = @()
            }
            foreach($streamobj in $streamObjects){
                $pipelineObj.StreamObjects += $streamobj
            }

            # return the result
            $pipelineObj
        }
    }
}

function InternalGet-GeoffreyStreamObject{
    [cmdletbinding()]
    param(
        [System.IO.Stream[]]$sourceStream,
        [System.IO.FileInfo[]]$sourcePath
    )
    end{
        $sourceStreamCount = 0
        $sourcePathCount = 0

        if($sourceStream -is [array]){
            $sourceStreamCount = 1 
            $sourceStreamCount = $sourceStream.Count
        }
        if($sourcePath -ne $null){
            $sourcePathCount = 1
            if($sourcePath -is [array]){
                $sourcePathCount = $sourcePath.Count
            }
        }
        
        $returnObj = @()

        if($sourceStreamCount -eq 1 -and $sourcePathCount -le 0){
            # we just have one stream passed in
            if($sourceStream -is [array]){
                $sourceObj = New-Object psobject -Property @{
                    SourcePath = [System.IO.FileInfo]$null
                    _ReadStream = [System.IO.Stream]($sourceStream[0])
                }
                $returnobj += $sourceObj
            }
            else{
                $sourceObj = New-Object psobject -Property @{
                    SourcePath = [System.IO.FileInfo]$null
                    _ReadStream = [System.IO.Stream]($sourceStream)
                }
                $returnobj += $sourceObj
            }
        }
        elseif($sourcePathCount -eq 1 -and $sourceStreamCount -le 0){
            # we just have one file name passed in
            if($sourcePath -is [array]){
                $sourceObj = New-Object psobject -Property @{
                    SourcePath = [System.IO.FileInfo]($sourcePath[0])
                    _ReadStream = [System.IO.Stream]$null
                }
                $returnobj += $sourceObj
            }
            else{
                $sourceObj = New-Object psobject -Property @{
                    SourcePath = [System.IO.FileInfo]($sourcePath)
                    _ReadStream = [System.IO.Stream]$null
                }
                $returnobj += $sourceObj
            }
        }
        elseif($sourceStreamCount -gt 0 -and ($sourceStreamCount -eq $sourcePathCount)){
            $currentIndex = 0
            for($currentIndex = 0; $currentIndex -lt $sourceStreamCount;$currentIndex++){
                $sourceObj = New-Object psobject -Property @{
                    SourcePath = [System.IO.FileInfo]($sourcePath[$currentIndex])
                    _ReadStream = [System.IO.Stream]($sourceStream[$currentIndex])
                }
                $returnobj += $sourceObj
            }
        }
        else{
            throw ('There is a mismatch between the number of source streams [{0}] and source paths [{1}]' -f $sourceStreamCount,$sourcePathCount)
        }

        # add the GetReadStreamMethod
        foreach($sobj in $returnObj){
            $sobj | Add-Member -MemberType ScriptMethod -Name GetReadStream -Value {
                if($this._ReadStream -eq $null){
                    if(-not ([string]::IsNullOrWhiteSpace($this.SourcePath))){
                        $this._ReadStream = [System.IO.File]::OpenRead($this.SourcePath)
                    }
                    else{
                        throw ('Unable to open stream because [SourcePath] is empty')
                    }
                }

                # return the stream now
                $this._ReadStream
            }
        }

        # return the results
        $returnObj
    }
}

<#
.SYNOPSIS
This will read the given files and return streams. It's up to the caller to close the streams
#>
function Invoke-GeoffreySource{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [System.IO.FileInfo[]]$sourceFiles
    )
    end{
        $returnobj = @()
        foreach($file in $sourceFiles){
            $filepath = $file
            if($file -is [System.IO.FileInfo]){
                $filepath = $file.FullName
            }

            # read the file and return the stream to the pipeline
            $returnobj += (InternalGet-GeoffreyStreamObject -sourcePath $file)
        }

        # return the results
        InternalGet-GeoffreyPipelineObject -streamObjects $returnobj
    }
}
set-alias src Invoke-GeoffreySource

function Ensure-ParentDirExists{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [System.IO.FileInfo[]]$filePath
    )
    process{
        foreach($file in $filePath){
            if(-not ($file.Directory.Exists)){
                $file.Directory.Create() | Write-Verbose
            }
        }
    }
}

<#
If dest is a single file then place all streams into the same file
If dest has more than one value then it should be 1:1 with the streams
#>
function Invoke-GeoffreyDest{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true,Position=1)]
        [object]$pipelineObj, # type is GeoffreyPipelineObject

        [Parameter(Position=0)]
        [string[]]$destination,

        [Parameter(Position=2)]
        [switch]$append
    )
    end{
        $currentIndex = 0
        $destStreams = @{}
        $returnobj = @()
        
        $filesWritten = @()
        # see if we are writing to a single file or multiple            
        $sourceStreams = $pipelineObj.StreamObjects

        foreach($currentStreamPipeObj in $sourceStreams){
            [System.IO.Stream]$currentStream = ($currentStreamPipeObj.GetReadStream())
            $actualDest = $destination[$currentIndex]
            
            # see if it's a directory and if so append the source file to it
            if(Test-Path $actualDest -PathType Container){
                $actualDest = (Join-Path $actualDest ($currentStreamPipeObj.SourcePath.Name))
            }

            if($filesWritten -notcontains $actualDest){
                # if the file exists delete it first because it's the first write
                if(-not $append -and (test-path $actualDest)){                        
                    # in the special case that src and dest are the same, don't delete the file first
                    [string]$filesource = $currentStreamPipeObj.SourcePath
                    if([string]::Compare($filesource,$actualDest,$true) -ne 0){
                        Remove-Item $actualDest | Write-Verbose
                    }
                }
                $filesWritten += $actualDest
            }

            # write the stream to the dest and close the source stream
            try{                    
                [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $currentStream
                # todo: buffer this
                $strContents = $reader.ReadToEnd()
                $reader.Close() | Out-Null
                $reader.Dispose() | Out-Null
                $currentStream.Close() | Out-Null
                $currentStream.Dispose() | Out-Null

                if( (($destStreams[$actualDest]) -eq $null) -or (-not ($destStreams[$actualDest].CanWrite)) ){
                    $actualDest | Ensure-ParentDirExists
                    Start-Sleep -Milliseconds 2
                    $destStreams[$actualDest] = [System.IO.File]::OpenWrite($actualDest)
                }
                [ValidateNotNull()]$streamToWrite = $destStreams[$actualDest]
                [System.IO.StreamWriter]$writer = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $streamToWrite

                $writer.BaseStream.Seek(0,[System.IO.SeekOrigin]::End) | Out-Null                    
                $writer.Write($strContents) | Out-Null
                $writer.Flush() | Out-Null
                $writer.Write("`r`n") | Out-Null
                $writer.Flush() | Out-Null

                # return the file to the pipeline
                $returnobj += (Get-Item $actualDest)

                # if the dest only has one value then don't increment it
                if($destination.Count -gt 1){
                    $currentIndex++ | Out-Null
                }                
                
                $writer.Close() | Out-Null
                $writer.Dispose() | Out-Null
            }
            catch{
                throw ("An error occured during writing to the destination. Exception: {0}`r`n{1}" -f $_.Exception,(Get-PSCallStack|Out-String))
            }                
        }

        # return the results
        InternalGet-GeoffreyPipelineObject -streamObjects $returnobj
    }
}
Set-Alias dest Invoke-GeoffreyDest

function Invoke-GeoffreyCombine{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true,Position=1)]
        [object]$pipelineObj # type is GeoffreyPipelineObject
    )
    process{}
    end{
        $currentIndex = 0

        # setup the destination stream here
        [System.IO.MemoryStream]$memstream = New-Object -TypeName 'System.IO.MemoryStream'
        [System.IO.StreamWriter]$writer = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memstream

        $writer.BaseStream.Seek(0,[System.IO.SeekOrigin]::End) | Out-Null

        try{
            # see if we are writing to a single file or multiple
            $sourceStreams = $pipelineObj.StreamObjects
            foreach($currentStreamPipeObj in $sourceStreams){
                $currentStream = ($currentStreamPipeObj.GetReadStream())
                [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $currentStream

                # todo: buffer this
                $strContents = $reader.ReadToEnd()
                $writer.Write($strContents) | Out-Null
                $writer.Flush() | Out-Null
                $writer.Write("`r`n") | Out-Null
                $writer.Flush() | Out-Null

                $currentStream.Flush() | Out-Null
                $currentStream.Dispose() | Out-Null
            }
            $memstream.Position = 0

            # memstream will be closed when the writer is in Dispose() so make a new stream and return that
            [System.IO.MemoryStream]$streamtoreturn = New-Object -TypeName 'System.IO.MemoryStream'
            $memstream.CopyTo($streamtoreturn)
            $streamtoreturn.Flush()
            $streamtoreturn.Position = 0

            $reader.Dispose()
            $writer.Dispose()

            # return the combined object here
            InternalGet-GeoffreyPipelineObject -streamObjects (InternalGet-GeoffreyStreamObject -sourceStream $streamtoreturn)
        }
        catch{
                throw ("An error occured during writing to the destination. Exception: {0}`r`n{1}" -f $_.Exception,(Get-PSCallStack|Out-String))
        }

    }
}
Set-Alias combine Invoke-GeoffreyCombine

function InternalEnsure-GeoffreyWatchLoaded{
    [cmdletbinding()]
    param()
    process{
        if(-not $watcherLoaded){
            [System.IO.FileInfo[]]$geoffreyWatchSearchPaths = "$scriptDir\Geoffry.Watch.dll","$scriptDir\OutputRoot\Geoffry.Watch.dll"
            if(Test-Path env:GeoffreyBinPath){
                $geoffreyWatchSearchPaths += (Join-Path $env:GeoffreyBinPath 'Geoffry.Watch.dll')
            }

            [bool]$foundwatchassembly = $false
            [System.IO.FileInfo]$assemblyPath = $null
            foreach($path in $geoffreyWatchSearchPaths){
                if(Test-Path $path){
                    $assemblyPath = $path
                    $foundwatchassembly = $true
                    break
                }
            }

            if($foundwatchassembly){
                Add-Type -Path $assemblyPath
                $watcherLoaded = $true
                $watchertype = [Geoffry.Watch.Watcher]
                Register-ObjectEvent -SourceIdentifier "geoffreywatcher-$([guid]::NewGuid())" -InputObject $watchertype -EventName Changed -Action {InternalWatch-OnChanged -sourcetoken ($Event.SourceEventArgs.Token)  }
            }
            else{
                throw ('Unable to find Geoffry.Watch.dll in search paths [{0}]' -f ($geoffreyWatchSearchPaths -join ';'))
            }
        }
    }
}

# watch related items
[hashtable]$global:watchHandlers = @{}

function global:InternalWatch-OnChanged{
    [cmdletbinding()]
    param(
        $sourcetoken
    )
    process{
        'Changed [{0}]' -f $sourcetoken | Write-Verbose
        "{0}`n" -f [DateTime]::Now.ToLongTimeString()|Out-File C:\temp\geoffrey-watcher.txt -Append

        $wrapper = (InernalGet-GeoffreyWatchFolderHandlerWrapper -token ([guid]$sourcetoken))

        if($wrapper){
            'Invoking handler for token [{0}]' -f $sourcetoken | Write-Verbose

            'Executing task(s) [{0}]' -f ($wrapper.TaskToExecute -join ',') | Write-Verbose

            Invoke-GeoffreyTask -name ($wrapper.TaskToExecute) -force
        }     
    }
}

function global:Register-GeoffreyWatchFolder{
    [cmdletbinding()]
    param(
        [Parameter(Position = 0)]
        [System.IO.DirectoryInfo]$rootDirectory = ($pwd),

        [Parameter(Position = 1)]
        [string]$globbingPattern = '**/*',

        [Parameter(Position = 2)]
        [int]$waitPeriodMilliseconds = 500,

        [Parameter(Position=3,Mandatory=$true)]
        [string[]]$taskToExecute
    )
    begin{
        InternalEnsure-GeoffreyWatchLoaded
    }
    process{
        [Geoffry.Watch.WatchDefinition]$watcherdef = New-Object -TypeName 'Geoffry.Watch.WatchDefinition'
        $watcherdef.GlobbingPattern = $globbingPattern
        $watcherdef.RootDirectory = $rootDirectory

        'Using pattern [{0}] to watch folder [{1}]' -f ($watcherdef.GlobbingPattern), ($watcherdef.RootDirectory) | Write-Verbose
        [Geoffry.Watch.WatchDefinition[]]$watchlist = @()
        $watchlist+=$watcherdef
        $waitPeriod = [System.TimeSpan]::FromMilliseconds($waitPeriodMilliseconds)
        $token = [Geoffry.Watch.Watcher]::Subscribe($waitPeriod, $watchlist)

        $wrapper = New-Object -TypeName psobject -Property @{
            Token = $token
            WatcherDef = $watcherdef
            TaskToExecute = $taskToExecute
        }
        $wrapper | Format-Table |Write-Verbose
        $watchHandlers[$token]=$wrapper

        $token
    }
}
Set-Alias watch Register-GeoffreyWatchFolder

function global:Unregister-GeoffreyWatchFolder{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [guid]$token
    )
    process{
        if($token -ne $null){
            [Geoffry.Watch.Watcher]::Cancel($token)
            if($watchHandlers.ContainsKey($token)){
                'Removing handler for token [{0}]' -f $token | Write-Verbose
                $watchHandlers.Remove($token)
            }
        }
    }
}
Set-Alias unwatch UnRegister-GeoffreyWatchFolder

function Unregister-GeoffreyAllWatchFolder{
    [cmdletbinding()]
    param()
    process{
        $watchHandlers.Clear()
        [Geoffry.Watch.Watcher]::CancelAll()
        # cancell all powershell events as well
        #"geoffreywatcher-$([guid]::NewGuid())"
        $allevents = Get-Event
        foreach($someevent in $allevents){
            [string]$sourceid = $someevent.SourceIdentifier
            
            if(-not ([string]::IsNullOrWhiteSpace($sourceid))){
                if($sourceid.StartsWith('geoffreywatcher')){
                    Remove-Event -SourceIdentifier $sourceid
                }
            }
        }

        $jobs = Get-Job
        foreach($job in $jobs){
            $name = $job.Name
            if(-not ([string]::IsNullOrWhiteSpace($name))){
                if($name.StartsWith('geoffreywatcher')){
                    $job.StopJob()
                    Remove-Job $job
                }
            }
        }
    }
}
Set-Alias unwatchall Unregister-GeoffreyAllWatchFolder

# when he module is reloaded all existing handlers should be cancelled for this session
InternalEnsure-GeoffreyWatchLoaded
Unregister-GeoffreyAllWatchFolder

function global:InernalGet-GeoffreyWatchFolderHandlerWrapper{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [guid]$token
    )
    process{
        # return the handler if it exists
        if($token -ne $null -and $watchHandlers.ContainsKey($token)){            
            $watchHandlers[$token]
        }        
    }
}

function InternalGet-GeoffreyWatchHandlers{
    [cmdletbinding()]
    param()    
    process{
        $watchHandlers
    }
}

if( ($env:IsDeveloperMachine -eq $true) ){
    # you can set the env var to expose all functions to importer. easy for development.
    # this is required for pester testing
    Export-ModuleMember -function *
}
else{
    Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*,New-*,Import-*,Register-*,Unregister-* -Alias psbuild
}

Export-ModuleMember -Alias *
