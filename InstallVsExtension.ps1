# Based on https://gist.github.com/ScottHutchinson/b22339c3d3688da5c9b477281e258400
# Based on http://nuts4.net/post/automated-download-and-installation-of-visual-studio-extensions-via-powershell

function Invoke-VSInstallExtension {
    param([String] $PackageName)
 
    $ErrorActionPreference = "Stop"
 
    $baseProtocol = "https:"
    $baseHostName = "marketplace.visualstudio.com"
 
    $Uri = "$($baseProtocol)//$($baseHostName)/items?itemName=$($PackageName)"
    $VsixLocation = "$($env:Temp)\$([guid]::NewGuid()).vsix"
 
    $VSInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
 
    if (-Not $VSInstallDir) {
        Write-Error "Visual Studio InstallDir registry key missing"
        Exit 1
    }
 
    Write-Host "Grabbing VSIX extension at $($Uri)"
    $HTML = Invoke-WebRequest -Uri $Uri -UseBasicParsing -SessionVariable session
 
    Write-Host "Attempting to download $($PackageName)..."
    $anchor = $HTML.Links |
    Where-Object { $_.class -eq 'install-button-container' } |
    Select-Object -ExpandProperty href

    if (-Not $anchor) {
        Write-Error "Could not find download anchor tag on the Visual Studio Extensions page"
        Exit 1
    }
    Write-Host "Anchor is $($anchor)"
    $href = "$($baseProtocol)//$($baseHostName)$($anchor)"
    Write-Host "Href is $($href)"
    Invoke-WebRequest $href -OutFile $VsixLocation -WebSession $session
 
    if (-Not (Test-Path $VsixLocation)) {
        Write-Error "Downloaded VSIX file could not be located"
        Exit 1
    }
    Write-Host "VSInstallDir is $($VSInstallDir)"
    Write-Host "VsixLocation is $($VsixLocation)"
    Write-Host "Installing $($PackageName)..."
    Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $($VsixLocation)" -Wait
 
    Write-Host "Cleanup..."
    Remove-Item $VsixLocation
 
    Write-Host "Installation of $($PackageName) complete!"
}


Get-Process devenv -ErrorAction Ignore | Stop-Process -ErrorAction Ignore

Invoke-VSInstallExtension -PackageName 'AlexPendleton.LocateinTFS2017'
Invoke-VSInstallExtension -PackageName 'cpmcgrath.Codealignment-2019'
Invoke-VSInstallExtension -PackageName 'EWoodruff.VisualStudioSpellCheckerVS2017andLater'
Invoke-VSInstallExtension -PackageName 'MadsKristensen.OpeninVisualStudioCode'
Invoke-VSInstallExtension -PackageName 'MadsKristensen.TrailingWhitespaceVisualizer'
Invoke-VSInstallExtension -PackageName 'ViktarKarpach.DebugAttachManager'

Write-Host "Installing TrudUtils"

$currentPath = Get-Location
$repo = "juliomutley/TRUDUtilsD365"
$releases = "https://api.github.com/repos/$repo/releases"
$path = "C:\Temp\Addin"

If (!(test-path $path)) {
    New-Item -ItemType Directory -Force -Path $path
}
else {
    Get-ChildItem $path -Recurse | Remove-Item
}

Set-Location $path

Write-Host Determining latest release
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag = (Invoke-WebRequest -Uri $releases -UseBasicParsing | ConvertFrom-Json)[0].tag_name

$files = @("InstallToVS.exe", "TRUDUtilsD365.dll", "TRUDUtilsD365.pdb")

Write-Host Downloading files
foreach ($file in $files) {
    $download = "https://github.com/$repo/releases/download/$tag/$file"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $download -Out $file
    Unblock-File $file
}
Start-Process "InstallToVS.exe" -Verb runAs

Set-Location $currentPath

Write-Host "Installing Default Tools and Internal Dev tools"

Get-ChildItem "K:\DeployablePackages" -Include "*.vsix" -Recurse | ForEach-Object {
    Write-Host "installing:"
    Split-Path -Path $_ -Leaf -Resolve
    $VSInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
    Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $_" -Wait
}