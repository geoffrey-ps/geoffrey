Remove-Module alfred; Import-Module C:\Data\personal\mycode\alfred\alfred.psm1

$destFilesToRemove = 'C:\temp\alfred\dest\site-from-ps.css','C:\temp\alfred\dest\combined.css'

if(Test-Path C:\temp\site-from-ps.css){ Remove-Item -Path C:\temp\site-from-ps.css }

requires alfred-less
requires alfred-coffee
requires alfred-sass

task democopy {
    src c:\temp\site.css | 
        dest C:\temp\alfred\dest\site-from-ps.css    
}

task democoncat {
    dir C:\temp\alfred\css\lib *.css | 
        src | 
        concat C:\temp\alfred\dest\combined.css
}

alfredrun democopy
alfredrun democoncat