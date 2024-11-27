# Based on https://gist.github.com/ScottHutchinson/b22339c3d3688da5c9b477281e258400
# Based on http://nuts4.net/post/automated-download-and-installation-of-visual-studio-extensions-via-powershell

function Invoke-VSInstallExtension {
    param(
        [Parameter(Position=1)]
        [ValidateSet('2019','2022')]
        [System.String]$Version,  
    [String] $PackageName)
 
    $ErrorActionPreference = "Stop"
 
    $baseProtocol = "https:"
    $baseHostName = "marketplace.visualstudio.com"
 
    $Uri = "$($baseProtocol)//$($baseHostName)/items?itemName=$($PackageName)"
    $VsixLocation = "$($env:Temp)\$([guid]::NewGuid()).vsix"

    switch ($Version) {
        '2019' {
            $VSInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
        }
        '2022' {
            $VSInstallDir = "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\"
        }
    }

    If ((test-path $VSInstallDir)) {

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


        Write-Host "************    VSInstallDir is:  $($VSInstallDir)"
        Write-Host "************    VsixLocation is: $($VsixLocation)"
        Write-Host "************    Installing: $($PackageName)..."
        Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $($VsixLocation)" -Wait

        Write-Host "Cleanup..."
        Remove-Item $VsixLocation
    
        Write-Host "Installation of $($PackageName) complete!"
    }
}

Get-Process devenv -ErrorAction Ignore | Stop-Process -ErrorAction Ignore

Invoke-VSInstallExtension -Version 2019 -PackageName 'AlexPendleton.LocateinTFS2017'
Invoke-VSInstallExtension -Version 2022 -PackageName 'Zhenkas.LocateInTFS'
Invoke-VSInstallExtension -Version 2019 -PackageName 'cpmcgrath.Codealignment-2019'
Invoke-VSInstallExtension -Version 2022 -PackageName 'cpmcgrath.Codealignment'
Invoke-VSInstallExtension -Version 2019 -PackageName 'EWoodruff.VisualStudioSpellCheckerVS2017andLater'
Invoke-VSInstallExtension -Version 2022 -PackageName 'EWoodruff.VisualStudioSpellCheckerVS2022andLater'
Invoke-VSInstallExtension -Version 2019 -PackageName 'MadsKristensen.OpeninVisualStudioCode'
Invoke-VSInstallExtension -Version 2022 -PackageName 'MadsKristensen.OpeninVisualStudioCode'
Invoke-VSInstallExtension -Version 2019 -PackageName 'MadsKristensen.TrailingWhitespaceVisualizer'
Invoke-VSInstallExtension -Version 2022 -PackageName 'MadsKristensen.TrailingWhitespace64'
Invoke-VSInstallExtension -Version 2019 -PackageName 'ViktarKarpach.DebugAttachManager'
Invoke-VSInstallExtension -Version 2022 -PackageName 'ViktarKarpach.DebugAttachManager2022'

Write-Host "Installing TrudUtils"

$currentPath = Get-Location
#$repo = "juliomutley/TRUDUtilsD365" # VS2019
$repo = "TrudAX/TRUDUtilsD365" # VS 2022


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

# Accessing the Documents folder using environment variables
$documentsFolder = Join-Path $env:USERPROFILE 'Documents'

$xmlFilePath = "$documentsFolder\Visual Studio Dynamics 365\DynamicsDevConfig.xml"
$valueToCheck = "C:\Temp\Addin"

# Load the XML file
[xml]$xml = Get-Content -Path $xmlFilePath

# Check if the value exists
if (-not ($xml.DynamicsDevConfig.AddInPaths.string -contains $valueToCheck)) {
    # Value doesn't exist, add it
    $newElement = $xml.CreateElement("d2p1", "string", "http://schemas.microsoft.com/2003/10/Serialization/Arrays")
    $newElement.InnerText = $valueToCheck
    $xml.DynamicsDevConfig.AddInPaths.AppendChild($newElement)

    # Save the modified XML back to a file
    $xml.Save($xmlFilePath)
    Write-Host "Element added successfully."
}

Set-Location $currentPath

Write-Host "Installing Default Tools and Internal Dev tools"

$VSInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"

Get-ChildItem "K:\DeployablePackages" -Include "*.vsix" -Exclude "*.17.0.vsix" -Recurse | ForEach-Object {
    Write-Host "installing: $_"
    Split-Path -Path $VSInstallDir -Leaf -Resolve
    Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $_" -Wait
}

$VSInstallDir = "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\"

Get-ChildItem "K:\DeployablePackages" -Include "*.17.0.vsix" -Recurse | ForEach-Object {
    Write-Host "installing: $_"
    Split-Path -Path $VSInstallDir -Leaf -Resolve
    Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $_" -Wait
}

#region vscode extensions
$vsCodeExtensions = @(
    "adamwalzer.string-converter"
    ,"DotJoshJohnson.xml"
    ,"IBM.output-colorizer"
    ,"mechatroner.rainbow-csv"
    ,"ms-vscode.PowerShell"
    ,"piotrgredowski.poor-mans-t-sql-formatter-pg"
    ,"streetsidesoftware.code-spell-checker"
    ,"ZainChen.json"
)

$vsCodeExtensions | ForEach-Object {
    code --install-extension $_
}
#endregion