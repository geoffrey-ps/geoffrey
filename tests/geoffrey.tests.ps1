[cmdletbinding()]
param()

Set-StrictMode -Version Latest

function Get-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}
$scriptDir = ((Get-ScriptDirectory) + "\")

. (Join-Path $scriptDir 'import-geoffrey.ps1')

requires ajax-min
requires less
# begin tests
Describe 'New-GeoffreyTask tests'{
    It 'Can register a new task with a definition'{
        [string]$name = 'namehere'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -defintion $definition
        $global:geoffreycontext.Tasks.Count | Should be 1
        $global:geoffreycontext.Tasks[$name].Definition | Should not be null
        $global:geoffreycontext.Tasks[$name].DependsOn | Should be $null
    }
    
    It 'Can register a new task with a dependson with one value'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname'
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -dependsOn $dependson
        $global:geoffreycontext.Tasks.Count | Should be 1
        $global:geoffreycontext.Tasks[$name].Definition | Should be $null
        $global:geoffreycontext.Tasks[$name].DependsOn.Count | Should be 1
    }

    It 'Can register a new task with a dependson with multiple values'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname','otherdepname','thirddep'
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -dependsOn $dependson
        $global:geoffreycontext.Tasks.Count | Should be 1
        $global:geoffreycontext.Tasks[$name].Definition | Should be $null
        $global:geoffreycontext.Tasks[$name].DependsOn.Count | Should be 3
    }

    It 'can register a new task with a definition and dependson with one value'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -defintion $definition -dependsOn $dependson
        $global:geoffreycontext.Tasks.Count | Should be 1
        $global:geoffreycontext.Tasks[$name].Definition | Should not be null
        $global:geoffreycontext.Tasks[$name].DependsOn.Count | Should be 1
    }

    It 'can register a new task with a definition and dependson with multiple values'{
        [string]$name = 'namehere'
        [string[]]$dependson='depname','otherdepname','thirddep'
        [scriptblock]$definition={'some def here'|Write-Verbose}
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -defintion $definition -dependsOn $dependson
        $global:geoffreycontext.Tasks.Count | Should be 1
        $global:geoffreycontext.Tasks[$name].DependsOn.Count | Should be 3
    }
}

Describe 'Invoke-GeoffreyTask tests'{
    BeforeEach{
        $global:geoffreycontext.HasBeenInitalized = $false
        Reset-Geoffrey
    }

    It 'Can invoke a defined task'{
        [string]$name = 'namehere'
        $global:somevarhere=0
        [scriptblock]$definition={$global:somevarhere=5}
        $global:geoffreycontext.Tasks.Clear()
        $global:geoffreycontext.Tasks.Count | Should be 0
        New-GeoffreyTask -name $name -defintion $definition
        $global:somevarhere | Should be 0
        Invoke-GeoffreyTask -name $name
        $global:somevarhere | Should be 5
        Remove-Variable -Name somevarhere -Scope global
    }

    It 'can invoke a task that has no def and one dependencies'{
        $global:myvar = 0
        New-GeoffreyTask -name deptask -defintion {$global:myvar = 5 }
        New-GeoffreyTask -name thetask -dependsOn deptask
        $global:myvar | should be 0
        Invoke-GeoffreyTask -name thetask
        $global:myvar | should be 5
        remove-variable -Name myvar -scope global
    }

    It 'can invoke a task that has a def and one dependency'{
        $global:myvar = 0
        $global:myothervar = 0
        New-GeoffreyTask -name deptask -defintion {$global:myvar = 5 }
        New-GeoffreyTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask
        $global:myvar | should be 0
        $global:myothervar | should be 0
        Invoke-GeoffreyTask -name thetask
        $global:myvar | should be 5
        $global:myothervar | should be 100
        remove-variable -Name myvar -scope global
        remove-variable -Name myothervar -scope global
    }

    It 'can invoke a task that has a def and multiple dependencies'{
        $global:myvar = 0
        $global:myothervar = 0
        $global:myothervar2 = 0
        New-GeoffreyTask -name deptask -defintion {$global:myvar = 5 }
        New-GeoffreyTask -name deptask2 -defintion {$global:myothervar2 = 50 }
        New-GeoffreyTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask,deptask2

        $global:myvar | should be 0
        $global:myothervar | should be 0
        $global:myothervar2 | should be 0
        Invoke-GeoffreyTask -name thetask
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
        New-GeoffreyTask -name deptask -defintion {$global:myvar = 5 }
        New-GeoffreyTask -name deptask2 -defintion {$global:myothervar2 = 50 } -dependsOn deptask
        New-GeoffreyTask -name thetask -defintion {$global:myothervar = 100} -dependsOn deptask2

        $global:myvar | should be 0
        $global:myothervar | should be 0
        $global:myothervar2 | should be 0
        Invoke-GeoffreyTask -name thetask
        $global:myvar | should be 5
        $global:myothervar2 | should be 50
        $global:myothervar | should be 100
        remove-variable -Name myvar -scope global
        remove-variable -Name myothervar -scope global
        remove-variable -Name myothervar2 -scope global
    }

    It 'a task can modify existing variables' {
        $global:counter = 0
        New-GeoffreyTask -name mytask -defintion {$global:counter++ }
        Invoke-GeoffreyTask mytask,mytask
        $counter | Should be 1
    }

    It 'init will only run once' {
        Mock Invoke-GeoffreyTask -ParameterFilter {$name -eq 'init'}{}

        Invoke-GeoffreyTask init,init
        Assert-MockCalled Invoke-GeoffreyTask -Exactly 1 -ParameterFilter {$name -eq 'init'}
    }
}

Describe 'Invoke-GeoffreySource tests'{
    $script:tempfilecontent1 = 'some content here1'
    $script:tempfilepath1 = 'Invoke-GeoffreySource\temp1.txt'

    $script:tempfilecontent2 = 'some content here2'
    $script:tempfilepath2 = 'Invoke-GeoffreySource\temp2.txt'

    $script:tempfilecontent3 = 'some content here3'
    $script:tempfilepath3 = 'Invoke-GeoffreySource\temp3.txt'

    Setup -File -Path $script:tempfilepath1 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath2 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath3 -Content $script:tempfilecontent3

    It 'given one file returns a stream'{
        $path1 = (Join-Path $TestDrive $script:tempfilepath1)
        $result = Invoke-GeoffreySource -sourceFiles $path1
        $result | Should not be $null
        $result.StreamObjects[0] | Should not be $null
        $result.StreamObjects[0].SourcePath | Should be $path1
    }

    It 'given more than one file returns the streams stream'{
        Setup -File -Path 'invoke-geoffreydest\return-streams\temp01.txt' -Content $script:tempfilecontent1
        Setup -File -Path 'invoke-geoffreydest\nodest\temp02.txt' -Content $script:tempfilecontent2
        Setup -File -Path 'invoke-geoffreydest\nodest\temp03.txt' -Content $script:tempfilecontent3

        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\return-streams\temp01.txt')
        $path2 = (Join-Path $TestDrive 'invoke-geoffreydest\nodest\temp02.txt')
        $path3 = (Join-Path $TestDrive 'invoke-geoffreydest\nodest\temp03.txt')

        $result = Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3
        $result | Should not be $null
        $result  | % {$_.StreamObjects[0] | Should not be $null}
        $result.StreamObjects[0].SourcePath | Should be $path1,$path2,$path3
    }
}

Describe 'Invoke-GeoffreyDest tests'{
    $script:tempfilecontent1 = 'some content here1'
    $script:tempfilepath1 = 'Invoke-GeoffreyDest\temp1.txt'
    $script:tempfilepath1_1 = 'Invoke-GeoffreyDest\temp1_1.txt'

    $script:tempfilecontent2 = 'some content here2'
    $script:tempfilepath2 = 'Invoke-GeoffreyDest\temp2.txt'
    $script:tempfilepath1_2 = 'Invoke-GeoffreyDest\temp1_2.txt'

    $script:tempfilecontent3 = 'some content here3'
    $script:tempfilepath3 = 'Invoke-GeoffreyDest\temp3.txt'
    $script:tempfilepath1_3 = 'Invoke-GeoffreyDest\temp1_3.txt'

    Setup -File -Path $script:tempfilepath1 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath2 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath3 -Content $script:tempfilecontent3

    # todo: need to create duplicates because streams are not closing correclty, fix that then this
    Setup -File -Path $script:tempfilepath1_1 -Content $script:tempfilecontent1
    Setup -File -Path $script:tempfilepath1_2 -Content $script:tempfilecontent2
    Setup -File -Path $script:tempfilepath1_3 -Content $script:tempfilecontent3

    It 'will copy a single file to the dest'{
        Setup -File -Path 'invoke-geoffreydest\copysingle\temp.txt' -Content $script:tempfilecontent1
        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\copysingle\temp.txt')
        $result = Invoke-GeoffreySource -sourceFiles $path1
        $dest = (Join-Path $TestDrive 'dest01.txt')
        $dest | Should not exist
        Invoke-GeoffreyDest -pipelineObj $result -destination $dest
        $dest | Should exist
    }

    It 'will create dest dir if it does not exist'{
        Setup -File -Path 'invoke-geoffreydest\nodest\temp.txt' -Content $script:tempfilecontent1

        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\nodest\temp.txt')
        $result = Invoke-GeoffreySource -sourceFiles $path1
        $destFolder = (Join-Path $TestDrive 'nodest\newfolder01')
        $dest = (Join-Path $destFolder 'dest01.txt')
        $destFolder | Should not exist
        $dest | Should not exist
        Invoke-GeoffreyDest -pipelineObj $result -destination $dest
        $destFolder | Should exist
        $dest | Should exist
    }

    # TODO: streams not being closed correctly are causing issues here
    It 'will copy multiple files to multiple destinations'{
        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\temp01.txt')
        $path2 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\temp02.txt')
        $path3 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\temp03.txt')
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01')
        $script:tempfilecontent1|Out-File -FilePath $path1
        $script:tempfilecontent1|Out-File -FilePath $path2
        $script:tempfilecontent1|Out-File -FilePath $path3

        $result = Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3
        $dest1 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\dest01-01.txt')
        $dest2 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\dest01-02.txt')
        $dest3 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple01\dest01-03.txt')

        $dest1 | Should not exist
        $dest2 | Should not exist
        $dest3 | Should not exist
        Invoke-GeoffreyDest -pipelineObj $result -destination $dest1,$dest2,$dest3
        $dest1 | Should exist
        $dest2 | Should exist
        $dest3 | Should exist
    }
    
    It 'will copy multiple files to a single dest'{
        Setup -File -Path 'invoke-geoffreydest\copymultiple02\temp01.txt' -Content $script:tempfilecontent1
        Setup -File -Path 'invoke-geoffreydest\copymultiple02\temp02.txt' -Content $script:tempfilecontent2
        Setup -File -Path 'invoke-geoffreydest\copymultiple02\temp03.txt' -Content $script:tempfilecontent3
        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple02\temp01.txt')
        $path2 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple02\temp02.txt')
        $path3 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple02\temp03.txt')
        $result = Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3
        $dest1 = (Join-Path $TestDrive 'invoke-geoffreydest\copymultiple02\dest02-01.txt')

        $dest1 | Should not exist
        Invoke-GeoffreyDest -pipelineObj $result -destination $dest1
        $dest1 | Should exist
    }

    It 'can call src and pipe to directly to dest'{
        Setup -File -Path 'invoke-geoffreydest\src-to-dest\temp01.txt' -Content $script:tempfilecontent1
        $path1 = (Join-Path $TestDrive 'invoke-geoffreydest\src-to-dest\temp01.txt')

        {Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyDest -destination $path1} | should not throw
    }
}

Describe 'Invoke-GeoffreyCombine tests'{
    It 'can combine two files'{
        $relpath01 = 'invoke-geoffreycombine\temp01.txt'
        Setup -File -Path $relpath01 -Content $script:tempfilecontent1
        [System.IO.FileInfo]$path01 = (Join-Path $TestDrive $relpath01)

        $relpath02 = 'invoke-geoffreycombine\temp02.txt'
        Setup -File -Path $relpath02 -Content $script:tempfilecontent1
        [System.IO.FileInfo]$path02 = (Join-Path $TestDrive $relpath02)

        [System.IO.FileInfo]$destfile = (Join-Path $TestDrive 'invoke-geoffreycombine\dest.css')
        Test-Path ($destfile.FullName) | should not be $true

        $result = (Invoke-GeoffreyDest -destination $destFile -pipelineObj (Invoke-GeoffreyCombine -pipelineObj (Invoke-GeoffreySource -sourceFiles $path01,$path01) ))
        Test-Path ($destfile.FullName) | should be $true

        $destFile.Length -gt $path01.Length | should be $true
        $destFile.Length -gt $path02.Length | should be $true
    }

    It 'can combine two files with piping'{
        $relpath01 = 'invoke-geoffreycombine-pipe\temp01.txt'
        Setup -File -Path $relpath01 -Content $script:tempfilecontent1
        [System.IO.FileInfo]$path01 = (Join-Path $TestDrive $relpath01)

        $relpath02 = 'invoke-geoffreycombine-pipe\temp02.txt'
        Setup -File -Path $relpath02 -Content $script:tempfilecontent1
        [System.IO.FileInfo]$path02 = (Join-Path $TestDrive $relpath02)

        [System.IO.FileInfo]$destfile = (Join-Path $TestDrive 'invoke-geoffreycombine-pipe\dest.css')
        Test-Path ($destfile.FullName) | should not be $true

        # $result = (Invoke-GeoffreyDest -destination $destFile -pipelineObj (Invoke-GeoffreyCombine -pipelineObj (Invoke-GeoffreySource -sourceFiles $path01,$path01) ))
        $result = Invoke-GeoffreySource -sourceFiles $path01,$path02 | Invoke-GeoffreyCombine | Invoke-GeoffreyDest -destination $destfile
        Test-Path ($destfile.FullName) | should be $true

        $destFile.Length -gt $path01.Length | should be $true
        $destFile.Length -gt $path02.Length | should be $true
    }
}

Describe 'Invoke-GeoffreyMinifyCss tests'{
    $script:samplecss01 = @'
html {
	margin: 0;
	padding: 0;
	}
body {
	font: 75% georgia, sans-serif;
	line-height: 1.88889;
	color: #555753;
	background: #fff url(blossoms.jpg) no-repeat bottom right; 
	margin: 0; 
	padding: 0;
	}
'@
    
    $script:samplecss02 = @'
a:hover, a:focus, a:active { 
	text-decoration: underline; 
	color: #9685BA;
	}
abbr {
	border-bottom: none;
	}


/* specific divs */
.page-wrapper { 
	background: url(zen-bg.jpg) no-repeat top left; 
	padding: 0 175px 0 110px;  
	margin: 0; 
	position: relative;
	}

.intro { 
	min-width: 470px;
	width: 100%;
	}
'@
    $script:samplecss03 = @'
header h1 { 
	background: transparent url(h1.gif) no-repeat top left;
	margin-top: 10px;
	display: block;
	width: 219px;
	height: 87px;
	float: left;

	text-indent: 100%;
	white-space: nowrap;
	overflow: hidden;
	}
header h2 { 
	background: transparent url(h2.gif) no-repeat top left; 
	margin-top: 58px; 
	margin-bottom: 40px; 
	width: 200px; 
	height: 18px; 
	float: right;

	text-indent: 100%;
	white-space: nowrap;
	overflow: hidden;
	}
header {
	padding-top: 20px;
	height: 87px;
}

.summary {
	clear: both; 
	margin: 20px 20px 20px 10px; 
	width: 160px; 
	float: left;
	}
'@
    $script:samplecss04 = @'
    /*!
    Important comment here
    */
html {
	margin: 0;
	padding: 0;
	}
body {
	font: 75% georgia, sans-serif;
	line-height: 1.88889;
	color: AntiqueWhite;
	background: #fff url(blossoms.jpg) no-repeat bottom right;
	margin: 0;
	padding: 0;
	}
'@

    It 'Can invoke Invoke-GeoffreyMinifyCss with a single file'{
        $samplecss01path = 'minifycss\sample01.css'
        Setup -File -Path $samplecss01path -Content $script:samplecss01
        $samplecss01path = 'minifycss\sample01.css'
        $path1 = (Join-Path $TestDrive $samplecss01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyCss)
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        $mincontent.Contains("`n") | Should be $false
        $minContent.Length -lt $script:samplecss01.Length | Should be $true

        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }

    It 'Can invoke Invoke-GeoffreyMinifyCss with multiple files'{
        $samplecss01 = 'mincss-multi\01.css'
        $samplecss02 = 'mincss-multi\02.css'
        $samplecss03 = 'mincss-multi\03.css'
        Setup -File -Path $samplecss01 -Content $script:samplecss01
        Setup -File -Path $samplecss02 -Content $script:samplecss02
        Setup -File -Path $samplecss03 -Content $script:samplecss03
        $path1 = (Join-Path $TestDrive $samplecss01)
        $path2 = (Join-Path $TestDrive $samplecss02)
        $path3 = (Join-Path $TestDrive $samplecss03)
        $result = (Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3 | Invoke-GeoffreyMinifyCss)

        foreach($alfpipeobj in $result.StreamObjects){
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($alfpipeobj.GetReadStream())
            $minContent = $reader.ReadToEnd()

            $alfpipeobj | Should not be null
            $alfpipeobj.GetReadStream() | Should not be $null
            $alfpipeobj.SourcePath | Should not be $null
            $minContent | Should not be $null
            $mincontent.Contains("`n") | Should be $false
            # close the streams as well
            $reader.Dispose()
            $alfpipeobj.GetReadStream().Dispose()
        }
    }

    It 'Can invoke Invoke-GeoffreyMinifyCss and pass settingsJson'{
        $samplecss04path = 'settingsjson\sample04.css'
        Setup -File -Path $samplecss04path -Content $script:samplecss04
        $path1 = (Join-Path $TestDrive $samplecss04path)
        # CommentMode=1 is CssComments.None
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyCss -settingsJson '{ "CommentMode":  1 }' )
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        $mincontent.Contains("`n") | Should be $false
        $minContent.Length -lt $script:samplecss04.Length | Should be $true
        $minContent.Contains('/*!') | Should be $false
        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }

    It 'Can invoke Invoke-GeoffreyMinifyCss and pass params to ajaminx01'{
        $samplecss04path = 'settingsjson-02\sample04.css'
        Setup -File -Path $samplecss04path -Content $script:samplecss04
        $path1 = (Join-Path $TestDrive $samplecss04path)
        # CommentMode=1 is CssComments.None
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyCss -CommentMode 'None' -ColorNames NoSwap )
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        $mincontent.Contains("`n") | Should be $false
        $minContent.Length -lt $script:samplecss04.Length | Should be $true
        $minContent.Contains('/*!') | Should be $false
        $minContent.ToLower().Contains('antiquewhite') | Should be $true
        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }
}

Describe 'Invoke-GeoffreyMinifyJavaScript tests'{
    # samples from http://javascriptbook.com/code/
    $script:samplejs01 = @'
var today = new Date();
var hourNow = today.getHours();
var greeting;

if (hourNow > 18) {
    greeting = 'Good evening!';
} else if (hourNow > 12) {
    greeting = 'Good afternoon!';
} else if (hourNow > 0) {
    greeting = 'Good morning!';
} else {
    greeting = 'Welcome!';
}

document.write('<h3>' + greeting + '</h3>');
'@
    $script:samplejs02 = @'
// Create a variable for the subtotal and make a calculation
var subtotal = (13 + 1) * 5; // Subtotal is 70

// Create a variable for the shipping and make a calculation
var shipping = 0.5 * (13 + 1); // Shipping is 7

// Create the total by combining the subtotal and shipping values
var total = subtotal + shipping; // Total is 77

// Write the results to the screen
var elSub = document.getElementById('subtotal');
elSub.textContent = subtotal;

var elShip = document.getElementById('shipping');
elShip.textContent = shipping;

var elTotal = document.getElementById('total');
elTotal.textContent = total;

/*
NOTE: textContent does not work in IE8 or earlier
You can use innerHTML on lines 12, 15, and 18 but note the security issues on p228-231
elSub.innerHTML = subtotal;
elShip.innerHTML = shipping;
elTotal.innerHTML = total;
*/
'@
    $script:samplejs03 = @'
// Create variables and assign their values
var inStock;
var shipping;
inStock = true;
shipping = false;

// Get the element that has an id of stock
var elStock = document.getElementById('stock');
// Set class name with value of inStock variable
elStock.className = inStock;

// Get the element that has an id of shipping
var elShip = document.getElementById('shipping');
// Set class name with value of shipping variable
elShip.className = shipping;
'@
$script:samplejs04 = @'
/*!
Important comment here
*/
Debug.write("debug statement here");
var today = new Date();
var hourNow = today.getHours();
var greeting;

if (hourNow > 18) {
    greeting = 'Good evening!';
} else if (hourNow > 12) {
    greeting = 'Good afternoon!';
} else if (hourNow > 0) {
    greeting = 'Good morning!';
} else {
    greeting = 'Welcome!';
}

document.write('<h3>' + greeting + '</h3>');
'@
    It 'Can invoke Invoke-GeoffreyMinifyJavaScript with a single file'{
        $samplejs01path = 'minifyjs\sample01.js'
        Setup -File -Path $samplejs01path -Content $script:samplejs01
        $path1 = (Join-Path $TestDrive $samplejs01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyJavaScript)
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        $mincontent.Contains("`n") | Should be $false
        $minContent.Length -lt $script:samplecss01.Length | Should be $true

        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }

    It 'Can invoke Invoke-GeoffreyMinifyJavaScript with multiple files'{
        $samplejs01 = 'minjs-multi\01.js'
        $samplejs02 = 'minjs-multi\02.js'
        $samplejs03 = 'minjs-multi\03.js'
        Setup -File -Path $samplejs01 -Content $script:samplejs01
        Setup -File -Path $samplejs02 -Content $script:samplejs02
        Setup -File -Path $samplejs03 -Content $script:samplejs03
        $path1 = (Join-Path $TestDrive $samplejs01)
        $path2 = (Join-Path $TestDrive $samplejs02)
        $path3 = (Join-Path $TestDrive $samplejs03)
        $result = (Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3 | Invoke-GeoffreyMinifyJavaScript)

        foreach($alfpipeobj in $result){
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($alfpipeobj.StreamObjects[0].GetReadStream())
            $minContent = $reader.ReadToEnd()

            $alfpipeobj | Should not be null
            $alfpipeobj.StreamObjects[0].GetReadStream() | Should not be $null
            $alfpipeobj.StreamObjects[0].SourcePath | Should not be $null
            $minContent | Should not be $null
            $mincontent.Contains("`n") | Should be $false
            # close the streams as well
            $reader.Dispose()
            $alfpipeobj.StreamObjects[0].GetReadStream().Dispose()
        }
    }

    It 'can pass settings via settingsJson'{
        $samplejs01path = 'minifyjs\settings01.js'
        Setup -File -Path $samplejs01path -Content $script:samplejs04
        $path1 = (Join-Path $TestDrive $samplejs01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyJavaScript -settingsJson '{ "PreserveImportantComments":false}')
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        #$mincontent.Contains("`n") | Should be $false
        $minContent.Length -lt $script:samplejs04.Length | Should be $true
        $minContent.Contains('/*!') | Should be $false
        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }

    It 'parameters are passed to ajaxmin'{
        $samplejs01path = 'minifyjs\settings02.js'
        Setup -File -Path $samplejs01path -Content $script:samplejs04
        $path1 = (Join-Path $TestDrive $samplejs01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyMinifyJavaScript -PreserveImportantComments $false )
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $minContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $minContent | Should not be $null
        $minContent.Length -lt $script:samplejs04.Length | Should be $true
        $minContent.Contains('/*!') | Should be $false
        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }
}
Describe 'Invoke-GeoffreyLess tests'{
    # from http://lesscss.org/
    $script:sampleless01 = @'
@base: #f938ab;

.box-shadow(@style, @c) when (iscolor(@c)) {
  -webkit-box-shadow: @style @c;
  box-shadow:         @style @c;
}
.box-shadow(@style, @alpha: 50%) when (isnumber(@alpha)) {
  .box-shadow(@style, rgba(0, 0, 0, @alpha));
}
.box {
  color: saturate(@base, 5%);
  border-color: lighten(@base, 30%);
  div { .box-shadow(0 0 5px, 30%) }
}
'@

    # from http://designshack.net/articles/css/introducing-the-less-css-grid/
    $script:sampleless02 = @'
@columnWidth: 60px;
@gutter: 10px;

@allColumns: @columnWidth * 12;
@allGutters: (@gutter * 12) * 2;
@totalWidth: @allColumns + @allGutters;

.theWidth (@theColumn: 1, @theGutter: 0) {
  width: (@columnWidth * @theColumn) + (@gutter * @theGutter);
}


.grid_1 { .theWidth(1,0); }
.grid_2 { .theWidth(2,2); }
.grid_3 { .theWidth(3,4); }
.grid_4 { .theWidth(4,6); }
.grid_5 { .theWidth(5,8); }
.grid_6 { .theWidth(6,10); }
.grid_7 { .theWidth(7,12); }
.grid_8 { .theWidth(8,14); }
.grid_9 { .theWidth(9,16); }
.grid_10 { .theWidth(10,18); }
.grid_11 { .theWidth(11,20); }
.grid_12 { .theWidth(12,22); }

.column {
    margin: 0 @gutter;
    overflow: hidden;
    float: left;
    display: inline;
}
.row {
    width: @totalWidth;
    margin: 0 auto;
    overflow: hidden;
}
.row .row {
    margin: 0 (@gutter * -1);
    width: auto;
    display: inline-block;
}
'@

    $script:sampleless03 = @'
@main-text-color: red;
@main-text-size: 12px;
@main-text-bg: green;

p {
  color: @main-text-color;
  font-size: @main-text-size;
  background-color: @main-text-bg;
}
'@

    It 'Can invoke Invoke-GeoffreyLess with a single file'{
        $sampleless01path = 'less\less01.less'
        Setup -File -Path $sampleless01path -Content $script:sampleless01

        $path1 = (Join-Path $TestDrive $sampleless01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1 | Invoke-GeoffreyLess)
        # ensure content is there
        [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($result.StreamObjects[0].GetReadStream())
        $compiledContent = $reader.ReadToEnd()

        $result | Should not be null
        $result.StreamObjects[0].GetReadStream() | Should not be $null
        $result.StreamObjects[0].SourcePath | Should not be $null
        $compiledContent | Should not be $null
        $compiledContent.Contains('@') | Should be $false
        $compiledContent.Length -lt $script:sampleless01.Length | Should be $true

        # close the streams as well
        $result.StreamObjects[0].GetReadStream().Dispose()
        $reader.Dispose()
    }

    It 'Can invoke Invoke-GeoffreyLess with multiple files'{
        $sampleless01path = 'less\less01.less'
        $sampleless02path = 'less\less01.less'
        $sampleless03path = 'less\less01.less'
        Setup -File -Path $sampleless01path -Content $script:sampleless01
        Setup -File -Path $sampleless02path -Content $script:sampleless02
        Setup -File -Path $sampleless03path -Content $script:sampleless03

        $path1 = (Join-Path $TestDrive $sampleless01path)
        $path2 = (Join-Path $TestDrive $sampleless01path)
        $path3 = (Join-Path $TestDrive $sampleless01path)
        $result = (Invoke-GeoffreySource -sourceFiles $path1,$path2,$path3 | Invoke-GeoffreyLess)
        foreach($alfpipeobj in $result){
            # ensure content is there
            [System.IO.StreamReader]$reader = New-Object -TypeName 'System.IO.StreamReader' -ArgumentList ($alfpipeobj.StreamObjects[0].GetReadStream())
            $compiledContent = $reader.ReadToEnd()

            $alfpipeobj | Should not be null
            $alfpipeobj.StreamObjects[0].GetReadStream() | Should not be $null
            $alfpipeobj.StreamObjects[0].SourcePath | Should not be $null
            $compiledContent | Should not be $null
            $compiledContent.Contains('@') | Should be $false
            $compiledContent.Length -lt $script:sampleless01.Length | Should be $true

            # close the streams as well
            $alfpipeobj.StreamObjects[0].GetReadStream().Dispose()
            $reader.Dispose()
        }
    }
}

Describe 'Invoke-Geoffrey tests'{
    $sampleScript01 = @'
    task default {
        $global:defaultwasrun = $true
    }
'@

    $sampleScript02 = @'
    task mydep{
        $global:mydepwasrun=$true
    }
    task mydep2{
        $global:mydep2wasrun=$true
    }
    task mydep3{
        $global:mydep3wasrun=$true
    }
    task default -dependsOn mydep,mydep2,mydep3
'@

    BeforeEach{
        $global:defaultwasrun = $false
        $global:mydepwasrun=$false
        $global:mydep2wasrun=$false
        $global:mydep3wasrun=$false
    }

    It 'Can run a file with just a default task in g.ps1'{
        $sampleScript01path = 'Invoke-Geoffrey\01\g.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript01
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        Push-Location
        try{
            Set-Location ($path1.Directory.FullName)
            $global:defaultwasrun | Should be $false
            Invoke-Geoffrey
            $global:defaultwasrun | Should be $true
        }
        finally{
            Pop-Location
        }
    }

    It 'Can run a file with just a default task and pass in the name of the file'{
        $sampleScript01path = 'Invoke-Geoffrey\02\sample.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript01
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        Push-Location
        try{
            Set-Location ($path1.Directory.FullName)
            $global:defaultwasrun | Should be $false
            Invoke-Geoffrey -scriptPath $path1.FullName
            $global:defaultwasrun | Should be $true
        }
        finally{
            Pop-Location
        }
    }

    It 'Can run a file with default that depends on other tasks'{
        $sampleScript01path = 'Invoke-Geoffrey\03\g.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript02
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        Push-Location
        try{
            Set-Location ($path1.Directory.FullName)
            Invoke-Geoffrey
            $global:mydepwasrun | Should be $true
            $global:mydep2wasrun | Should be $true
            $global:mydep3wasrun | Should be $true
        }
        finally{
            Pop-Location
        }
    }

    It 'Can run a file with default that depends on other tasks and pass in the script path'{
        $sampleScript01path = 'Invoke-Geoffrey\04\g.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript02
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        Invoke-Geoffrey -scriptPath $path1.FullName
        $global:mydepwasrun | Should be $true
        $global:mydep2wasrun | Should be $true
        $global:mydep3wasrun | Should be $true

    }

    It 'can use -list to get task names'{
        $sampleScript01path = 'Invoke-Geoffrey\05\g.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript02
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        $taskNames = Invoke-Geoffrey -scriptPath $path1.FullName -list
        $taskNames.Count | Should Be 4
        $taskNames.Contains('default') | should be $true
        $taskNames.Contains('mydep') | should be $true
        $taskNames.Contains('mydep2') | should be $true
        $taskNames.Contains('mydep3') | should be $true
    }

    It 'can execute a specific task by name'{
        $sampleScript01path = 'Invoke-Geoffrey\06\g.ps1'
        Setup -File -Path $sampleScript01path -Content $sampleScript02
        [System.IO.FileInfo]$path1 = (Join-Path $TestDrive $sampleScript01path)

        Invoke-Geoffrey -scriptPath $path1 -taskName mydep
    }
}

Describe 'InternalOverrideSettingsFromEnv tests'{
    It 'can apply settings from env vars'{
        $settingsObj = New-Object -TypeName psobject -Property @{
            MySetting = 'default'
            OtherSetting = 'other-default'
        }

        # create env vars
        $mysettingvalue = 'mysetting'
        $othersettingvalue ='othersetting'
        $env:mysetting = $mysettingvalue
        $env:othersetting = $othersettingvalue

        InternalOverrideSettingsFromEnv -settingsObj $settingsObj -prefix ''
        $settingsObj.MySetting | Should Be $mysettingvalue
        $settingsObj.OtherSetting | Should Be $othersettingvalue

        Remove-Item env:mysetting
        Remove-Item env:othersetting
    }

    It 'can apply settings from env vars and use a prefix'{
        $settingsObj = New-Object -TypeName psobject -Property @{
            MySetting = 'default'
            OtherSetting = 'other-default'
        }

        $prefix = 'unittest'
        $mysettingkey='mysetting'
        $othersettingkey='othersetting'

        $mysettingvalue = 'mysetting-value'
        $othersettingvalue ='othersetting-value'

        $mysettingpath = ('env:{0}{1}' -f $prefix,$mysettingkey)
        $othersettingpath = ('env:{0}{1}' -f $prefix,$othersettingkey)
        Set-Item -Path $mysettingpath -Value $mysettingvalue
        Set-Item -Path $othersettingpath -Value $othersettingvalue

        InternalOverrideSettingsFromEnv -settingsObj $settingsObj -prefix $prefix
        Get-Item -Path $mysettingpath | Select-Object -ExpandProperty Value | Should Be $mysettingvalue
        Get-Item -Path $othersettingpath | Select-Object -ExpandProperty Value | Should Be $othersettingvalue

        Remove-Item -Path $mysettingpath
        Remove-Item -Path $othersettingpath
    }
}

Describe 'requires tests'{
    [string]$global:lastMockCalled = 'none'
    $global:lastMockArgs = $null

    BeforeEach{
        $global:lastMockCalled = 'none'
        $global:lastMockArgs = $null
    }

    Mock -ModuleName geoffrey InternalDownloadAndInvoke{
        $global:lastMockCalled = 'iex'
        $global:lastMockArgs = $args
        $message = 'inside custom iex'
        $message | Write-Host
    }

    Mock -ModuleName geoffrey Get-NuGetPackage{
        $global:lastMockCalled = 'Get-NugetPackage'
        $global:lastMockArgs = $args
    }

    Mock -ModuleName nuget-powershell Get-NuGetPackage{
        $global:lastMockCalled = 'Get-NugetPackage'
        $global:lastMockArgs = $args
    }

    It 'can accept a url'{
        requires 'https://someurl.com/install.ps1'
        $global:lastMockCalled | Should be 'iex'
        $global:lastMockArgs[0] | should be '-url:'
        $global:lastMockArgs[1] | should be 'https://someurl.com/install.ps1'
    }

    It 'will skip iex if false condition for url'{
        requires 'https://someurl.ps1' $false
        $global:lastMockCalled | Should be 'none'
    }

    It 'will skip iex if false condition for package'{
        requires 'somepackage' $false
        $global:lastMockCalled | Should be 'none'
    }

    It 'calls get-nugetpackage'{
        'inside get-nugetpackage' | write-host
        requires -nameorurl 'name-here' -version 'version here'
        $global:lastMockCalled | Should be 'Get-NuGetPackage'
        $global:lastMockArgs -contains '-name:' | Should be $true
        $global:lastMockArgs -contains 'geoffrey-name-here' | Should be $true
        $global:lastMockArgs -contains '-version:' | Should be $true
        $global:lastMockArgs -contains 'version here' | Should be $true
    }
}