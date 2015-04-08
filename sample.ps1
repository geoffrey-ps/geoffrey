Remove-Module alfred; Import-Module C:\Data\personal\mycode\alfred\alfred.psm1

$destFilesToRemove = 'C:\temp\alfred\dest\site-from-ps.css','C:\temp\alfred\dest\combined.css'

if(Test-Path C:\temp\site-from-ps.css){
    Remove-Item -Path C:\temp\site-from-ps.css
}

src c:\temp\site.css | dest C:\temp\site-from-ps.css

#Get-Content C:\temp\site-from-ps.css

Get-ChildItem C:\temp\alfred\css\lib *.css | src | dest C:\temp\alfred\dest\combined.css