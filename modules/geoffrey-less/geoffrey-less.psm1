[cmdletbinding()]
param()

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

if( ($env:IsDeveloperMachine -eq $true) ){
    # you can set the env var to expose all functions to importer. easy for development.
    # this is required for pester testing
    Export-ModuleMember -function *
}
else{
    Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*,New-*,Import-*,Register-*,Unregister-* -Alias psbuild
}

Export-ModuleMember -Alias *