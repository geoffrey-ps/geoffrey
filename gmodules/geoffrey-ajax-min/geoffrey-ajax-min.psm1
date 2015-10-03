[cmdletbinding()]
param()

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

if( ($env:IsDeveloperMachine -eq $true) ){
    # you can set the env var to expose all functions to importer. easy for development.
    # this is required for pester testing
    Export-ModuleMember -function *
}
else{
    Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*,New-*,Import-*,Register-*,Unregister-* -Alias psbuild
}

Export-ModuleMember -Alias *