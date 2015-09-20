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
        [string]$prefix
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
            (new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1") | iex
        }

        # verify it was loaded
        if(-not (get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            throw ('Unable to load nuget-powershell, unknown error')
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
        [switch]$prerelease
    )
    begin{
        # make sure nuget-powershell is loaded and ready to be called
        Ensure-NuGetPowerShellIsLoaded
    }
    process{
        if($global:geoffreycontext.RunTasks){
            [string]$url = $null
            if($PSBoundParameters.ContainsKey('nameorurl')){
                # see if the value is a url or the name of a nuget package
                [System.Uri]$uriresult = $null
                [Uri]::TryCreate($nameorurl,[UriKind]::Absolute,[ref] $uriresult)
                if($uriresult -ne $null){
                    $url = $nameorurl
                }
            }

            # if $url is empty then its a nuget package
            if([string]::IsNullOrWhiteSpace($url)){
                # add required params here
                $getnugetparams = @{
                    'name'=$nameorurl
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
            else{
                # invoke with iex
                if( ($global:geoffreysettings.EnableRequiresViaUrl) -eq $true){
                    if($condition -eq $true){
                    # before executing convert to uri and then get absolut uri from that to make sure
                    # that users have not injected any PS into the requires string
                    [System.Uri]$uriresult = $null
                    [Uri]::TryCreate($url,[UriKind]::Absolute,[ref] $uriresult)
                    if($uriresult -ne $null){
                        try{
                            'Executing [{0}] from requires' -f ($uriresult.AbsoluteUri) |Write-Verbose
                            (new-object Net.WebClient).DownloadString(($uriresult.AbsoluteUri)) | iex
                        }
                        catch{
                            throw ("An error occured while executing [{0}] from requires. Exception: [{1}].`r`n{2}" -f ($uriresult.AbsoluteUri),($_.Exception),(Get-PSCallStack))
                        }
                    }
                    else{
                        throw ('Unable to parse the provided url [{0}]' -f $url)
                    }
                    }
                    else{
                        'Skipping [requires {0}] because the condition evaluated to false' -f $url | Write-Verbose
                    }
                }
                else{
                    'Skipping [requires {0}] because [$global:geoffreysettings.EnableRequiresViaUrl] is false' -f $url | Write-Warning
                }
            }
        }
        else{
            'Skipping requires because ''geoffreycontext.RunTasks'' is false' | Write-Verbose
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
        [System.IO.DirectoryInfo[]]$path
    )
    process{
        foreach($p in $path){
            try{
                [System.IO.DirectoryInfo]$tools = (Join-Path $p 'tools')
                [System.IO.FileInfo]$installFile = (Join-Path $tools 'g.install.ps1')
                [System.IO.FileInfo[]]$psd1Files = (Get-ChildItem $tools *.psd1)
                [System.IO.FileInfo[]]$psm1Files = (Get-ChildItem $tools *.psm1)

                if(Test-Path $installFile){
                    # install file found, execute it
                    'Executing install file at [{0}]' -f ($installFile.FullName) | Write-Verbose
                    . ($installFile.FullName)
                }
                elseif($psd1Files.Length -gt 0){
                    foreach($psd1 in $psd1Files){
                        'Importing module at [{0}]' -f ($psd1.FullName) | Write-Verbose
                        Import-Module ($psd1.FullName) -Global -DisableNameChecking | Write-Verbose
                    }
                }
                elseif($psm1Files.Length -gt 0){
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
    Path to the script to execute, the default is '.\g.ps1'

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
        [System.IO.FileInfo]$scriptPath = '.\g.ps1',

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

[string]$script:ajaxminpath = $null
<#
.SYNOPSIS
    This will minify the css content passed in sourceStreams

.PARAMETER sourceStreams
    Streams that should be minfied.

.PARAMETER settingsJson
    String containing a searlized CssSettings object which should be used for the settings.
    When constructing the string you can create a CssSettings object with the desired settings
    and then get the json for it with $cssSettings | ConvertTo-Json. You should only keep the
    values in the json string that you want applied. Only writable fields should be included.
    These settings are applied *before* the specific parameters that are passed in.

.PARAMETER CommentMode
    CommentMode value for CssSettings that is passed to the minifier

.PARAMETER ColorNames
    ColorNames value for CssSettings that is passed to the minifier

.PARAMETER CommentMode
    CommentMode value for CssSettings that is passed to the minifier

.PARAMETER MinifyExpressions
    MinifyExpressions value for CssSettings that is passed to the minifier

.PARAMETER CssType
    CssType value for CssSettings that is passed to the minifier

.PARAMETER RemoveEmptyBlocks
    RemoveEmptyBlocks value for CssSettings that is passed to the minifier

.PARAMETER AllowEmbeddedAspNetBlocks
    AllowEmbeddedAspNetBlocks value for CssSettings that is passed to the minifier

.PARAMETER IgnoreAllErrors
    IgnoreAllErrors value for CssSettings that is passed to the minifier

.PARAMETER IndentSize
    IndentSize value for CssSettings that is passed to the minifier

.EXAMPLE
    dir "$sourcefolder\css\site.css" | src | cssmin | dest "$destfolder\site.min.css"

.EXAMPLE
    dir "$sourcefolder\css\site.css" | src | cssmin -CommentMode 'None' | dest "$destfolder\site.min.css"

.EXAMPLE
    dir "$sourcefolder\css\site.css" | src | cssmin -settingsJson '{ "CommentMode":  1 }'  | dest "$destfolder\site.min.css"
#>
function Invoke-GeoffreyMinifyCss{
# this will take in a set of streams, minify the css and then return new streams
# this uses ajaxmin see https://ajaxmin.codeplex.com/wikipage?title=AjaxMin%20DLL
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object]$pipelineObj,  # type is GeoffreyPipelineObject

        [Parameter(Position=1)]
        [string]$settingsJson,

        [ValidateSet('Important','None','All','Hacks')]
        [string]$CommentMode,

        [ValidateSet('Strict','Hex','Major','NoSwap')]
        [string]$ColorNames,

        [bool]$MinifyExpressions,

        [ValidateSet('FullStyleSheet','DeclarationList')]
        [string]$CssType,

        [bool]$RemoveEmptyBlocks,
        [bool]$AllowEmbeddedAspNetBlocks,
        [bool]$IgnoreAllErrors,
        [int]$IndentSize
    )
    begin{
        # ensure ajaxmin is loaded
        if([string]::IsNullOrEmpty($script:ajaxminpath)){
            $script:ajaxminpath = (Get-NuGetPackage -name ajaxmin -version '5.14.5506.26202' -binpath)
            $assemblyPath = ((Join-Path $ajaxminpath 'net40\AjaxMin.dll'))
            'Loading AjaxMin from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate ajaxmin at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
        $minifier = New-Object -TypeName 'Microsoft.Ajax.Utilities.Minifier'
    }
    end{
        [Microsoft.Ajax.Utilities.CssSettings]$csssettings = New-Object -TypeName 'Microsoft.Ajax.Utilities.CssSettings'
        if(-not [string]::IsNullOrWhiteSpace($settingsJson)){
            Add-Type -Path (Join-Path (Get-NuGetPackage newtonsoft.json -version '6.0.8' -binpath) Newtonsoft.Json.dll)
            $method = ([Newtonsoft.Json.JsonConvert].GetMethods()|Where-Object { ($_.Name -eq 'DeserializeObject') -and ($_.IsGenericMethod -eq $true) -and ($_.GetParameters().Length -eq 1)}).MakeGenericMethod('Microsoft.Ajax.Utilities.CssSettings')
            $csssettings = $method.Invoke([Newtonsoft.Json.JsonConvert]::DeserializeObject,$settingsJson)
        }

        # apply parameter settings now
        $csspropnames = ($csssettings.GetType().GetProperties().Name)
        foreach($inputParamName in $PSBoundParameters.Keys){
            if(($csspropnames -contains $inputParamName)){
                'Applying cssmin settings for [{0}] to value [{1}]' -f  $inputParamName,($PSBoundParameters[$inputParamName])| Write-Verbose
                # apply the setting to the codeSettings object
                ($csssettings.$inputParamName) = ($PSBoundParameters[$inputParamName])
            }
        }

        $sourceStreams = $pipelineObj.StreamObjects
        $streamObjects = @()
        foreach($cssstreampipeobj in $sourceStreams){
            $cssstream = ($cssstreampipeobj.GetReadStream())
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $cssstream
            $source = $reader.ReadToEnd()
            $reader.Dispose()

            $resultText = $minifier.MinifyStyleSheet($source,$csssettings)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'

            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0
            # return the stream to the pipeline
            $streamObjects += (InternalGet-GeoffreyStreamObject -sourceStream $memStream -sourcePath ($cssstreampipeobj.SourcePath))
        }

        # return the results
        InternalGet-GeoffreyPipelineObject -streamObjects $streamObjects
    }
}
Set-Alias minifycss Invoke-GeoffreyMinifyCss -Description 'This alias is deprecated use cssmin instead'
Set-Alias cssmin Invoke-GeoffreyMinifyCss

<#
.SYNOPSIS
    This will minify the JavaScript content passed in sourceStreams

.PARAMETER sourceStreams
    Streams that should be minfied.

.PARAMETER settingsJson
    String containing a searlized CodeSettings object which should be used for the settings.
    When constructing the string you can create a CssSettings object with the desired settings
    and then get the json for it with $codeSettings | ConvertTo-Json. You should only keep the
    values in the json string that you want applied. Only writable fields should be included.
    These settings are applied *before* the specific parameters that are passed in.

.PARAMETER $AlwaysEscapeNonAscii
    AllowEmbeddedAspNetBlocks value for CodeSettings that is passed to the minifier
.PARAMETER $AmdSupport
    AmdSupport value for CodeSettings that is passed to the minifier
.PARAMETER $CollapseToLiteral
    CollapseToLiteral value for CodeSettings that is passed to the minifier
.PARAMETER $ConstStatementsMozilla
    ConstStatementsMozilla value for CodeSettings that is passed to the minifier
.PARAMETER $EvalLiteralExpressions
    EvalLiteralExpressions value for CodeSettings that is passed to the minifier
.PARAMETER $IgnoreConditionalCompilation
    IgnoreConditionalCompilation value for CodeSettings that is passed to the minifier
.PARAMETER $IgnorePreprocessorDefines
    IgnorePreprocessorDefines value for CodeSettings that is passed to the minifier
.PARAMETER $MacSafariQuirks
    MacSafariQuirks value for CodeSettings that is passed to the minifier
.PARAMETER $MinifyCode
    MinifyCode value for CodeSettings that is passed to the minifier
.PARAMETER $PreprocessOnly
    PreprocessOnly value for CodeSettings that is passed to the minifier
.PARAMETER $PreserveFunctionNames
    PreserveFunctionNamesvalue for CodeSettings that is passed to the minifier
.PARAMETER $PreserveImportantComments
    PreserveImportantComments value for CodeSettings that is passed to the minifier
.PARAMETER $QuoteObjectLiteralProperties
    QuoteObjectLiteralPropertiesvalue for CodeSettings that is passed to the minifier
.PARAMETER $ReorderScopeDeclarations
    ReorderScopeDeclarationsvalue for CodeSettings that is passed to the minifier
.PARAMETER $RemoveFunctionExpressionNames
    RemoveFunctionExpressionNames value for CodeSettings that is passed to the minifier
.PARAMETER $RemoveUnneededCode
    RemoveUnneededCodevalue for CodeSettings that is passed to the minifier
.PARAMETER $StrictMode
    StrictModevalue for CodeSettings that is passed to the minifier
.PARAMETER $StripDebugStatements
    StripDebugStatements value for CodeSettings that is passed to the minifier
.PARAMETER $AllowEmbeddedAspNetBlocks
    AllowEmbeddedAspNetBlocksvalue for CodeSettings that is passed to the minifier
.PARAMETER $IgnoreAllErrors
    IgnoreAllErrors value for CodeSettings that is passed to the minifier
.PARAMETER $IndentSize
    IndentSize value for CodeSettings that is passed to the minifier
.PARAMETER $TermSemicolons
    TermSemicolons value for CodeSettings that is passed to the minifier

.EXAMPLE
    dir "$sourcefolder\js\jquery-1.10.2.js" | src | jsmin -settingsJson | dest "$destfolder\jquery-1.10.2.min.js"
.EXAMPLE
    dir "$sourcefolder\js\jquery-1.10.2.js" | src | jsmin -AlwaysEscapeNonAscii $true | dest "$destfolder\jquery-1.10.2.min.js"
.EXAMPLE
    dir "$sourcefolder\js\jquery-1.10.2.js" | src | jsmin -settingsJson '{ "PreserveImportantComments":false}' -AlwaysEscapeNonAscii $true | dest "$destfolder\jquery-1.10.2.min.js"
#>
function Invoke-GeoffreyMinifyJavaScript{
    [cmdletbinding()]
    param(
        # note: parameters that have the same name as CodeSettings properties
        #       will get passed to CodeSettings
        [Parameter(ValueFromPipeline=$true,Position=0)]
        [object]$pipelineObj,  # type is GeoffreyPipelineObject

        [Parameter(Position=1)]
        [string]$settingsJson,

        # options for jsmin
        [bool]$AlwaysEscapeNonAscii,
        [bool]$AmdSupport,
        [bool]$CollapseToLiteral,
        [bool]$ConstStatementsMozilla,
        [bool]$EvalLiteralExpressions,
        [bool]$IgnoreConditionalCompilation,
        [bool]$IgnorePreprocessorDefines,
        [bool]$MacSafariQuirks,
        [bool]$MinifyCode,
        [bool]$PreprocessOnly,
        [bool]$PreserveFunctionNames,
        [bool]$PreserveImportantComments,
        [bool]$QuoteObjectLiteralProperties,
        [bool]$ReorderScopeDeclarations,
        [bool]$RemoveFunctionExpressionNames,
        [bool]$RemoveUnneededCode,
        [bool]$StrictMode,
        [bool]$StripDebugStatements,
        [bool]$AllowEmbeddedAspNetBlocks,
        [bool]$IgnoreAllErrors,
        [int]$IndentSize,
        [bool]$TermSemicolons
    )
    begin{
        # ensure ajaxmin is loaded
        if([string]::IsNullOrEmpty($script:ajaxminpath)){
            $script:ajaxminpath = (Get-NuGetPackage -name ajaxmin -version '5.14.5506.26202' -binpath)
            $assemblyPath = ((Join-Path $ajaxminpath 'net40\AjaxMin.dll'))
            'Loading AjaxMin from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate ajaxmin at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
        $minifier = New-Object -TypeName 'Microsoft.Ajax.Utilities.Minifier'
    }
    end{
        [Microsoft.Ajax.Utilities.CodeSettings]$codeSettings = New-Object -TypeName 'Microsoft.Ajax.Utilities.CodeSettings'
        if(-not [string]::IsNullOrWhiteSpace($settingsJson)){
            # convertfrom-json doesn't work in powershell < 5 for CodeSettings. Instead use json.net
            Add-Type -Path (Join-Path (Get-NuGetPackage newtonsoft.json -version '6.0.8' -binpath) Newtonsoft.Json.dll)
            $method = ([Newtonsoft.Json.JsonConvert].GetMethods()|Where-Object { ($_.Name -eq 'DeserializeObject') -and ($_.IsGenericMethod -eq $true) -and ($_.GetParameters().Length -eq 1)}).MakeGenericMethod('Microsoft.Ajax.Utilities.CodeSettings')
            $codeSettings = $method.Invoke([Newtonsoft.Json.JsonConvert]::DeserializeObject,$settingsJson)
        }

        # apply settings now
        $cspropnames = (($codeSettings.GetType().GetProperties()).Name)
        foreach($inputParamName in $PSBoundParameters.Keys){
            if(($cspropnames -contains $inputParamName)){
                'Applying jsmin settings for [{0}] to value [{1}]' -f  $inputParamName,($PSBoundParameters[$inputParamName])| Write-Verbose
                # apply the setting to the codeSettings object
                ($codeSettings.$inputParamName) = ($PSBoundParameters[$inputParamName])
            }
        }

        $sourceStreams = $pipelineObj.StreamObjects
        $streamObjects = @()
        foreach($jsstreampipeobj in $sourceStreams){
            $jsstream = ($jsstreampipeobj.GetReadStream())
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $jsstream
            $source = $reader.ReadToEnd()
            $reader.Dispose()
            $resultText = $minifier.MinifyJavaScript($source,$codeSettings)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'
            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0

            $streamObjects += (InternalGet-GeoffreyStreamObject -sourceStream $memStream -sourcePath ($jsstreampipeobj.SourcePath))
        }

        # return the results
        InternalGet-GeoffreyPipelineObject -streamObjects $streamObjects
    }
}
Set-Alias minifyjs Invoke-GeoffreyMinifyJavaScript -Description 'This alias is deprecated use jsmin instead'
Set-Alias jsmin Invoke-GeoffreyMinifyJavaScript

$script:lessassemblypath = $null
function Invoke-GeoffreyLess{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]$pipelineObj  # type is GeoffreyPipelineObject
    )
    begin{
        if([string]::IsNullOrEmpty($script:lessassemblypath)){
            $script:lessassemblypath = (Get-NuGetPackage -name dotless -version '1.5.0-beta1' -binpath)
            $assemblyPath = ((Join-Path $script:lessassemblypath 'dotless.Core.dll'))
            'Loading dotless from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate dotless at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
    }
    end{
        $sourceStreams = $pipelineObj.StreamObjects
        $streamObjects = @()
        foreach($lessstreampipeobj in $sourceStreams){
            $lessstream = ($lessstreampipeobj.GetReadStream())
            # read the file and compile it
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $lessstream
            $source = $reader.ReadToEnd()
            $reader.Dispose()
            $compiledText = [dotless.Core.Less]::Parse($source)
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'
            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($compiledText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0

            $streamObjects += (InternalGet-GeoffreyStreamObject -sourceStream $memStream -sourcePath ($lessstreampipeobj.SourcePath))
        }

        # return the results
        InternalGet-GeoffreyPipelineObject -streamObjects $streamObjects
    }
}
Set-Alias less Invoke-GeoffreyLess

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
