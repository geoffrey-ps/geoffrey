[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    Split-Path ((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

function Load-AlfredModule{
    [cmdletbinding()]
    param(
        [string]$alfredModulePath = (Join-Path $scriptDir '..\alfred.psm1')
    )
    process{
        $env:IsDeveloperMachine = $true
        if(-not (Test-Path $alfredModulePath)){
            throw ('Unable to find alfred at [{0}]' -f $alfredModulePath)
        }
        if(Get-Module alfred){
            Remove-Module alfred -force
        }
        Import-Module $alfredModulePath -Force -DisableNameChecking
    }
}

Load-AlfredModule

# begin tests
Describe 'New-AlfredTask tests'{
    It 'Can register a new task with a definition'{
        [string]$name = 'namehere'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -defintion $definition
        $global:alfredcontext.Tasks.Count | Should be 1
        $global:alfredcontext.Tasks[$name].Definition | Should not be null
        $global:alfredcontext.Tasks[$name].DependsOn | Should be $null
    }
    
    It 'Can register a new task with a dependson with one value'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname'
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -dependsOn $dependson
        $global:alfredcontext.Tasks.Count | Should be 1
        $global:alfredcontext.Tasks[$name].Definition | Should be $null
        $global:alfredcontext.Tasks[$name].DependsOn.Count | Should be 1
    }

    It 'Can register a new task with a dependson with multiple values'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname','otherdepname','thirddep'
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -dependsOn $dependson
        $global:alfredcontext.Tasks.Count | Should be 1
        $global:alfredcontext.Tasks[$name].Definition | Should be $null
        $global:alfredcontext.Tasks[$name].DependsOn.Count | Should be 3
    }

    It 'can register a new task with a definition and dependson with one value'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -defintion $definition -dependsOn $dependson
        $global:alfredcontext.Tasks.Count | Should be 1
        $global:alfredcontext.Tasks[$name].Definition | Should not be null
        $global:alfredcontext.Tasks[$name].DependsOn.Count | Should be 1
    }

    It 'can register a new task with a definition and dependson with multiple values'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname','otherdepname','thirddep'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -defintion $definition -dependsOn $dependson
        $global:alfredcontext.Tasks.Count | Should be 1
        $global:alfredcontext.Tasks[$name].DependsOn.Count | Should be 3
    }
}

Describe 'Invoke-AlfredTask tests'{
    It 'Can invoke a defined task'{
        [string]$name = 'namehere'
        $global:somevarhere=0
        [scriptblock]$definition={$global:somevarhere=5}
        $global:alfredcontext.Tasks.Clear()
        $global:alfredcontext.Tasks.Count | Should be 0
        New-AlfredTask -name $name -defintion $definition
        $global:somevarhere | Should be 0
        Invoke-AlfredTask -name $name
        $global:somevarhere | Should be 5
        Remove-Variable -Name somevarhere -Scope global
    }

    It 'can invoke a task that has no def and one dependencies'{
        $global:myvar = 0
        New-AlfredTask -name deptask -defintion {$global:myvar = 5 }
        New-AlfredTask -name thetask -dependsOn deptask
        $global:myvar | should be 0
        Invoke-AlfredTask -name thetask
        $global:myvar | should be 5
        remove-variable -Name myvar -scope global
    }

    It 'can invoke a task that has a def and one dependency'{
        $global:myvar = 0
        $global:myothervar = 0
        New-AlfredTask -name deptask -defintion {$global:myvar = 5 }
        New-AlfredTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask
        $global:myvar | should be 0
        $global:myothervar | should be 0
        Invoke-AlfredTask -name thetask
        $global:myvar | should be 5
        $global:myothervar | should be 100
        remove-variable -Name myvar -scope global
        remove-variable -Name myothervar -scope global
    }

    It 'can invoke a task that has a def and multiple dependencies'{
        $global:myvar = 0
        $global:myothervar = 0
        $global:myothervar2 = 0
        New-AlfredTask -name deptask -defintion {$global:myvar = 5 }
        New-AlfredTask -name deptask2 -defintion {$global:myothervar2 = 50 }
        New-AlfredTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask,deptask2

        $global:myvar | should be 0
        $global:myothervar | should be 0
        $global:myothervar2 | should be 0
        Invoke-AlfredTask -name thetask
        $global:myvar | should be 5
        $global:myothervar2 | should be 50
        $global:myothervar | should be 100
        remove-variable -Name myvar -scope global
        remove-variable -Name myothervar -scope global
        remove-variable -Name myothervar2 -scope global
    }

    It 'can invoke a task that has a def and a dependency which has a dependency'{
        $global:myvar = 0
        $global:myothervar = 0
        $global:myothervar2 = 0
        New-AlfredTask -name deptask -defintion {$global:myvar = 5 }
        New-AlfredTask -name deptask2 -defintion {$global:myothervar2 = 50 } -dependsOn deptask
        New-AlfredTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask2

        $global:myvar | should be 0
        $global:myothervar | should be 0
        $global:myothervar2 | should be 0
        Invoke-AlfredTask -name thetask
        $global:myvar | should be 5
        $global:myothervar2 | should be 50
        $global:myothervar | should be 100
        remove-variable -Name myvar -scope global
        remove-variable -Name myothervar -scope global
        remove-variable -Name myothervar2 -scope global
    }
}

Describe 'Invoke-AlfredSource tests'{
    $script:tempfilecontent1 = 'some content here1'
    $script:tempfilepath1 = 'Invoke-AlfredSource\temp1.txt'

    $script:tempfilecontent2 = 'some content here2'
    $script:tempfilepath2 = 'Invoke-AlfredSource\temp2.txt'

    $script:tempfilecontent3 = 'some content here3'
    $script:tempfilepath3 = 'Invoke-AlfredSource\temp3.txt'

    Setup -File -Path $script:tempfilepath1 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath2 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath3 -Content $script:tempfilecontent3

    It 'given one file returns a stream'{
        $path1 = Join-Path $TestDrive $script:tempfilepath1
        $result = Invoke-AlfredSource -sourceFiles $path1
        $result | Should not be $null
        $result.SourceStream | Should not be $null
        $result.SourcePath | Should be $path1
        $result.SourceStream.Dispose()
    }

    It 'given more than one file returns the streams stream'{
        $path1 = Join-Path $TestDrive $script:tempfilepath1
        $path2 = Join-Path $TestDrive $script:tempfilepath2
        $path3 = Join-Path $TestDrive $script:tempfilepath3

        $result = Invoke-AlfredSource -sourceFiles $path1,$path2,$path3
        $result | Should not be $null
        $result  | % {$_.SourceStream | Should not be $null}
        $result.SourcePath | Should be $path1,$path2,$path3
        $result | % {$_.SourceStream.Dispose()}
    }
}

Describe 'Invoke-AlfredDest tests'{
    $script:tempfilecontent1 = 'some content here1'
    $script:tempfilepath1 = 'Invoke-AlfredDest\temp1.txt'
    $script:tempfilepath11 = 'Invoke-AlfredDest\temp11.txt'

    $script:tempfilecontent2 = 'some content here2'
    $script:tempfilepath2 = 'Invoke-AlfredDest\temp2.txt'
    $script:tempfilepath12 = 'Invoke-AlfredDest\temp12.txt'

    $script:tempfilecontent3 = 'some content here3'
    $script:tempfilepath3 = 'Invoke-AlfredDest\temp3.txt'
    $script:tempfilepath13 = 'Invoke-AlfredDest\temp13.txt'

    Setup -File -Path $script:tempfilepath1 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath2 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath3 -Content $script:tempfilecontent3

    # todo: need to create duplicates because streams are not closing correclty, fix that then this
    Setup -File -Path $script:tempfilepath11 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath12 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath13 -Content $script:tempfilecontent3

    It 'will copy a single file to the dest'{
        $path1 = Join-Path $TestDrive $script:tempfilepath1
        $result = Invoke-AlfredSource -sourceFiles $path1
        $dest = (Join-Path $TestDrive 'dest01.txt')
        $dest | Should not exist
        Invoke-AlfredDest -sourceStreams $result -destination $dest
        $dest | Should exist
    }

    # TODO: streams not being closed correctly are causing issues here
    It 'will copy multiple files to multiple destinations'{
        $path1 = Join-Path $TestDrive $script:tempfilepath1
        $path2 = Join-Path $TestDrive $script:tempfilepath2
        $path3 = Join-Path $TestDrive $script:tempfilepath3
        $result = Invoke-AlfredSource -sourceFiles $path1,$path2,$path3
        $dest1 = (Join-Path $TestDrive 'dest01-01.txt')
        $dest2 = (Join-Path $TestDrive 'dest01-02.txt')
        $dest3 = (Join-Path $TestDrive 'dest01-03.txt')

        $dest1 | Should not exist
        $dest2 | Should not exist
        $dest3 | Should not exist
        Invoke-AlfredDest -sourceStreams $result -destination $dest1,$dest2,$dest3
        $dest1 | Should exist
        $dest2 | Should exist
        $dest3 | Should exist
    }
    
    It 'will copy multiple files to a single dest'{
        $path1 = Join-Path $TestDrive $script:tempfilepath11
        $path2 = Join-Path $TestDrive $script:tempfilepath12
        $path3 = Join-Path $TestDrive $script:tempfilepath13
        $result = Invoke-AlfredSource -sourceFiles $path1,$path2,$path3
        $dest1 = (Join-Path $TestDrive 'dest02-01.txt')

        $dest1 | Should not exist
        Invoke-AlfredDest -sourceStreams $result -destination $dest1
        $dest1 | Should exist
    }
}

