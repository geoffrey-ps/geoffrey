[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function Get-ScriptDir{
    split-path $MyInvocation.ScriptName
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$global:alfredcontext = New-Object PSObject -Property @{
    HasBeenInitalized = $false
    Tasks = [hashtable]@{}
    RunTasks = $true
    HasRunInitTask = $false
    TasksExecuted = New-Object System.Collections.Generic.List[System.String]
}

# later we will use this to check if it has been initalized and throw an error if not
function InternalInitalizeAlfred{
    [cmdletbinding()]
    param()
    process{
        $global:alfredcontext.Tasks = [hashtable]@{}
        $global:alfredcontext.RunTasks = $true
        $global:alfredcontext.HasBeenInitalized = $true
        $global:alfredcontext.TasksExecuted.Clear()
    }
}

function Invoke-AlfredRequires{
    [cmdletbinding()]
    param(
        [string[]]$moduleName
    )
    process{
        if($global:alfredcontext.RunTasks){
            foreach($itemName in $moduleName){
                'Downloading and importing {0}' -f $itemName | Write-Host
            }
        }
        else{
            'Skipping requires because alfredruntasks is false' | Write-Verbose
        }
    }
}
Set-Alias requires Invoke-AlfredRequires

<#
.SYNOPSIS
    This is the command that users will use to run scripts.

.PARAMETER scriptPath
    Path to the script to execute, the default is '.\alfred.ps1'

.PARAMETER list
    This will return the list of tasks in the file

.PARAMETER list
    Name(s) of the task(s) that should be executed. This will accept either a single
    value or multiple values.
#>
function Invoke-Alfred{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo]$scriptPath = '.\alfred.ps1',

        [Parameter(Position=1)]
        [switch]$list,

        [Parameter(Position=2)]
        [string[]]$taskName
    )
    begin{
        InternalInitalizeAlfred
    }
    process{
        $taskNamePassed = ($PSBoundParameters.ContainsKey('taskName'))
        $runtasks = !($list -or $taskName)

        try{
            $global:alfredcontext.RunTasks =$runtasks
            # execute the script
            . $scriptPath

            if($list){
                # output the name of all the registered tasks
                $global:alfredcontext.Tasks.Keys
            }
            elseif($taskNamePassed){ # if -list is passed don't execute anything
                $runtaskpreviousvalue = $global:alfredcontext.RunTasks
                try{
                    $global:alfredcontext.RunTasks = $true
                    Invoke-AlfredTask $taskName
                }
                finally{
                    $global:alfredcontext.RunTasks = $runtaskpreviousvalue
                }
            }
            else{
                # execute the default task if it exists
                $defaultTask = $global:alfredcontext.Tasks.Item('default')
                if( $defaultTask -ne $null ){
                    Invoke-AlfredTask -name default
                }
            }
        }
        finally{
            $global:alfredcontext.RunTasks = $true
        }
    }
}
Set-Alias alfred Invoke-Alfred

<#
.SYNOPSIS
This will create a new task, register it with alfred and return the object itself. If there is already
a task with the given name it will be overwritten
#>
function New-AlfredTask{
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
    process{
        $result = New-Object psobject -Property @{
            Name = $name
            Definition = $defintion
            DependsOn = $dependsOn
        }
        $global:alfredcontext.Tasks[$name]=$result
    }
}
set-alias task New-AlfredTask

function Invoke-AlfredTask{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$name
    )
    process{
        if($global:alfredcontext.RunTasks -eq $true){
            # run the init task if not already
            if($global:alfredcontext.HasRunInitTask -ne $true){
                # set this before calling the task to ensure the if only passes once
                $global:alfredcontext.HasRunInitTask = $true

                $initTask = $global:alfredcontext.Tasks.Item('init')
                if( $initTask -ne $null -and ([string]::Compare($name,'init') -ne 0) ){
                    Invoke-AlfredTask -name init
                }
            }

            foreach($taskname in $name){
                # skip executing the task if already executed
                if($global:alfredcontext.TasksExecuted.Contains($taskname)){
                    'Skipping task [{0}] because it has already been executed' -f $taskname | Write-Verbose
                    continue;
                }

                $global:alfredcontext.TasksExecuted.Add($taskname)

                $tasktorun = $global:alfredcontext.Tasks[$taskname]

                if($tasktorun -eq $null){
                    throw ('Did not find a task with the name [{0}]' -f $taskname)
                }

                if($tasktorun.DependsOn -ne $null){
                    foreach($dtask in ($tasktorun.DependsOn)){
                        # avoid infinite loop
                        if([string]::Compare($taskname,$dtask) -ne 0){
                            Invoke-AlfredTask $dtask
                        }
                    }
                }

                if($tasktorun.Definition -ne $null){
                    'Invoking task [{0}]' -f $name | Write-Verbose
                    &(($global:alfredcontext.Tasks[$name]).Definition)
                }
            }
        }
    }
}
Set-Alias alfredrun Invoke-AlfredTask

function InternalGet-AlfredSourcePipelineObj{
    [cmdletbinding()]
    param(
        [System.IO.Stream[]]$sourceStream,
        [System.IO.FileInfo[]]$sourcePath
    )
    begin{
        if($sourceStream -ne $null){
            $currentIndex = 0
            if($sourceStream.Count -ne $sourcePath.Count){
                throw ('There is a mismatch between the number of source streams [{0}] and source paths [{1}]' -f $sourceStream.Count,$sourcePath.Count)
            }
        }
    }
    process{
        if($sourceStream -ne $null){
            $currentIndex = 0

            foreach($source in $sourceStream){
                # create an object and return it to the pipeline
                $sourceObj = New-Object psobject -Property @{
                    SourceStream = $source
                    SourcePath = ($sourcePath[$currentIndex])
                }
                $sourceObj.PSObject.TypeNames.Insert(0,'AlfredSourcePipeObj')
                $currentIndex++ | Out-Null

                # return the obj to the pipeline
                $sourceObj
            }
        }
    }
}

<#
.SYNOPSIS
This will read the given files and return streams. It's up to the caller to close the streams
#>
function Invoke-AlfredSource{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [System.IO.FileInfo[]]$sourceFiles
    )
    process{
        foreach($file in $sourceFiles){
            $filepath = $file
            if($file -is [System.IO.FileInfo]){
                $filepath = $file.FullName
            }

            # read the file and return the stream to the pipeline
            InternalGet-AlfredSourcePipelineObj -sourceStream ([System.IO.File]::OpenRead($filepath)) -sourcePath $file
        }
    }
}
set-alias src Invoke-AlfredSource

<#
If dest is a single file then place all streams into the same file
If dest has more than one value then it should be 1:1 with the streams
#>
function Invoke-AlfredDest{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object[]]$sourceStreams, # type is AlfredSourcePipeObj

        [Parameter(Position=0)]
        [string[]]$destination
    )
    process{
    # todo: if the dest folder doesn't exist then create it
        $currentIndex = 0
        $destStreams = @{}
        $strmsToClose = @()
        try{
            # see if we are writing to a single file or multiple
            foreach($currentStreamPipeObj in $sourceStreams){
                $currentStream = ($currentStreamPipeObj.SourceStream)
                $actualDest = $destination[$currentIndex]
            
                # see if it's a directory and if so append the source file to it
                if(Test-Path $actualDest -PathType Container){
                    $actualDest = (Join-Path $actualDest ($currentStreamPipeObj.SourcePath.Name))
                }

                # write the stream to the dest and close the source stream
                try{
                    if( ($destStreams[$actualDest]) -eq $null){
                        $destStreams[$actualDest] = [System.IO.File]::OpenWrite($actualDest)
                    }

                    [ValidateNotNull()]$streamToWrite = $destStreams[$actualDest]
                    [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $currentStream
                    [System.IO.StreamWriter]$writer = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $streamToWrite
                    $writer.BaseStream.Seek(0,[System.IO.SeekOrigin]::End) | Out-Null

                    # todo: buffer this
                    $strContents = $reader.ReadToEnd()
                    $writer.Write($strContents) | Out-Null
                    $writer.Flush() | Out-Null

                    $currentStream.Flush() | Out-Null

                    $strmsToClose += $reader
                    $strmsToClose += $writer

                    # return the file to the pipeline
                    Get-Item $actualDest
                }
                catch{
                    $_ | Write-Error
                }
                # if the dest only has one value then don't increment it
                if($destination.Count -gt 1){
                    $currentIndex++ | Out-Null
                }
            }
        }
        finally{
            foreach($strm in $strmsToClose){
                try{
                    $strm.Dispose()
                }
                catch [System.ObjectDisposedException]{
                    # this exception will be thrown if we dispose of a stream more than once.
                    # for ex when dest has multiple input files but only one dest,
                    # so its ok to ignore it
                }
            }
        }
    }
}
Set-Alias dest Invoke-AlfredDest

# this will take in a set of streams, minify the css and then return new streams
# this uses ajaxmin see https://ajaxmin.codeplex.com/wikipage?title=AjaxMin%20DLL
[string]$script:ajaxminpath = $null
function Invoke-AlfredMinifyCss{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object[]]$sourceStreams  # type is AlfredSourcePipeObj
    )
    begin{
        # ensure ajaxmin is loaded
        if([string]::IsNullOrEmpty($script:ajaxminpath)){
            $script:ajaxminpath = (Get-NuGetPackage -name ajaxmin -version '5.14.5506.26202')
            $assemblyPath = ((Join-Path $ajaxminpath 'bin\net40\AjaxMin.dll'))
            'Loading AjaxMin from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate ajaxmin at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
        $minifier = New-Object -TypeName 'Microsoft.Ajax.Utilities.Minifier'
    }
    process{
        foreach($cssstreampipeobj in $sourceStreams){
            $cssstream = ($cssstreampipeobj.SourceStream)
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $cssstream
            $source = $reader.ReadToEnd()
            $reader.Dispose()

            $resultText = $minifier.MinifyStyleSheet($source)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'

            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0
            # return the stream to the pipeline
            InternalGet-AlfredSourcePipelineObj -sourceStream $memStream -sourcePath ($cssstreampipeobj.SourcePath)
        }
    }
}
Set-Alias minifycss Invoke-AlfredMinifyCss

function Invoke-AlfredMinifyJavaScript{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object[]]$sourceStreams  # type is AlfredSourcePipeObj
    )
    begin{
        # ensure ajaxmin is loaded
        if([string]::IsNullOrEmpty($script:ajaxminpath)){
            $script:ajaxminpath = (Get-NuGetPackage -name ajaxmin -version '5.14.5506.26202')
            $assemblyPath = ((Join-Path $ajaxminpath 'bin\net40\AjaxMin.dll'))
            'Loading AjaxMin from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate ajaxmin at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
        $minifier = New-Object -TypeName 'Microsoft.Ajax.Utilities.Minifier'
    }
    process{
        foreach($jsstreampipeobj in $sourceStreams){
            $jsstream = ($jsstreampipeobj.SourceStream)
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $jsstream
            $source = $reader.ReadToEnd()
            $reader.Dispose()
            $resultText = $minifier.MinifyJavaScript($source)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'
            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0

            # return the stream to the pipeline
            InternalGet-AlfredSourcePipelineObj -sourceStream $memStream -sourcePath ($jsstreampipeobj.SourcePath)
        }
    }
}
Set-Alias minifyjs Invoke-AlfredMinifyJavaScript

$script:lessassemblypath = $null
function Invoke-AlfredLess{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object[]]$sourceStreams  # type is AlfredSourcePipeObj        
    )
    begin{
        if([string]::IsNullOrEmpty($script:lessassemblypath)){
            $script:lessassemblypath = (Get-NuGetPackage -name dotless -version '1.5.0-beta1')
            $assemblyPath = ((Join-Path $script:lessassemblypath 'bin\dotless.Core.dll'))
            'Loading dotless from [{0}]' -f $assemblyPath | Write-Verbose
            if(-not (Test-Path $assemblyPath)){
                throw ('Unable to locate dotless at expected location [{0}]' -f $assemblyPath)
            }
            # load the assemblies as well
            Add-Type -Path $assemblyPath | Out-Null
        }
    }
    process{
        foreach($lessstreampipeobj in $sourceStreams){
            $lessstream = ($lessstreampipeobj.SourceStream)
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

            # return the stream to the pipeline
            InternalGet-AlfredSourcePipelineObj -sourceStream $memStream -sourcePath ($lessstreampipeobj.SourcePath)
        }
    }
}
Set-Alias less Invoke-AlfredLess

# todo we should update this to export on the correct items and use
# $env:IsDeveloperMachine to expose to tests cases
Export-ModuleMember -function *
Export-ModuleMember -Alias *
