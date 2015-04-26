[cmdletbinding()]
param()

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

[hashtable]$script:alfredtasks = @{}

function Invoke-AlfredRequires{
    [cmdletbinding()]
    param(
        [string[]]$moduleName
    )
    process{
        foreach($itemName in $moduleName){
            'Downloading and importing {0}' -f $itemName | Write-Host
        }
    }
}
Set-Alias requires Invoke-AlfredRequires

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

        $script:alfredtasks[$name]=$result
    }
}
set-alias task New-AlfredTask

function Invoke-AlfredTask{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        $name
    )
    process{
        # todo: execute dependson
        # todo: skip executing if already executed
        'Invoking task [{0}]' -f $name | Write-Verbose
        &(($script:alfredtasks[$name]).Definition)
    }
}
Set-Alias alfredrun Invoke-AlfredTask
<#
.SYNOPSIS
This will read the given files and return streams. It's up to the caller to close the streams
#>
function Invoke-AlfredSource{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$sourceFiles
    )
    process{
        foreach($file in $sourceFiles){
            $filepath = $file
            if($file -is [System.IO.FileInfo]){
                $filepath = $file.FullName
            }
            # read the file and return the stream to the pipeline
            [System.IO.File]::OpenRead($filepath) 
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
        [System.IO.Stream[]]$sourceStreams,

        [Parameter(Position=0)]
        [string[]]$destination
    )
    begin{
        $strmsToClose = @()
    }
    end{
        foreach($stream in $strmsToClose){
            $stream.Dispose() | Out-Null
        }
    }
    process{
    # todo: if the dest folder doesn't exist then create it
        $currentIndex = 0
        $destStreams = @{}
        # see if we are writing to a single file or multiple
        foreach($currentStream in $sourceStreams){
            $actualDest = $destination[$currentIndex]
            
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

                # copyto doesn't work for concat
                #$currentStream.CopyTo($streamToWrite) | Out-Null
                $currentStream.Flush() | Out-Null
                #$streamToWrite.Dispose()
                $reader.Dispose() | Out-Null
                $writer.Dispose() | Out-Null
                
                #$strmsToClose+= $reader
                #$strmsToClose += $writer

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
}
Set-Alias dest Invoke-AlfredDest

function Invoke-AlfredConcat{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.IO.FileStream[]]$sourceStreams,

        [Parameter(Position=0)]
        [string]$destination
    )
    process{
        Invoke-AlfredDest -sourceStreams $sourceStreams -destination $destination
    }
}
Set-Alias concat Invoke-AlfredConcat

# this will take in a set of streams, minify the css and then return new streams
# this uses ajaxmin see https://ajaxmin.codeplex.com/wikipage?title=AjaxMin%20DLL
[string]$script:ajaxminpath = $null
function Invoke-AlfredMinifyCss{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.IO.FileStream[]]$sourceStreams
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
        foreach($cssstream in $sourceStreams){
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $cssstream
            $source = $reader.ReadToEnd()
            $resultText = $minifier.MinifyStyleSheet($source)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'
            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0

            # return the stream to the pipeline
            $memStream
        }
    }
}
Set-Alias minifycss Invoke-AlfredMinifyCss

function Invoke-AlfredMinifyJavaScript{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.IO.FileStream[]]$sourceStreams
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
        foreach($cssstream in $sourceStreams){
            # minify the stream and return
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList $cssstream
            $source = $reader.ReadToEnd()
            $resultText = $minifier.MinifyJavaScript($source)
            # create a stream from the text
            $memStream = New-Object -TypeName 'System.IO.MemoryStream'
            [System.IO.StreamWriter]$stringwriter = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $memStream
            $stringwriter.Write($resultText) | Out-Null
            $stringwriter.Flush() | Out-Null
            $memStream.Position = 0

            # return the stream to the pipeline
            $memStream
        }
    }
}
Set-Alias minifyjs Invoke-AlfredMinifyJavaScript

Export-ModuleMember -function *
Export-ModuleMember -Alias *
# begin sample script
<#
requires alfred-less
requires alfred-coffee
requires alfred-concat

task copy {
    'inside the copy task' | Write-Host
}

task coffee {
    'inside the coffee task' | Write-Host
}

task less {
    'inside the less task' | Write-Host
}

task default -dependsOn copy,less,coffee

$script:alfredtasks
#>
# requires alfred-less; alfred-coffee;alfred-concat
<#
$alfred = (new-object Net.WebClient).DownloadString("http://alfredps.com/getalfred.ps1") | iex

requires alfred-less
requires alfred-coffee
requires alfred-concat

task copy {
    src './less/site.less' |         # gets site.less (i think it would return Stream based objects but not sure)
      less './less/site.less' |      # converts from site.less to site.css (?where is the temp file stored? or is all streams)
      dest './css'                   # writes the file to the ./css/site.css
}
task coffee {
    src './coffee/*.coffee','./lib/coffee/*.coffee' |
      concat 'site.js' |
      coffee |
      dest './'
}

task default -depends copy,less,coffee
#>
