# Based on https://gist.github.com/ScottHutchinson/b22339c3d3688da5c9b477281e258400
# Based on http://nuts4.net/post/automated-download-and-installation-of-visual-studio-extensions-via-powershell
#
# Usage:
#   .\InstallVsExtension.ps1               # installs into the latest Visual Studio only
#   .\InstallVsExtension.ps1 -AllVersions  # installs into every Visual Studio 2022+ instance
param(
    [switch] $AllVersions
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-TargetVSInstances {
    param([switch] $All)

    # vswhere ships with the VS installer and resolves any edition (Community/Professional/Enterprise)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Warning "vswhere.exe not found, no Visual Studio instances detected"
        return @()
    }

    # Limit to real VS editions: '-products *' would also return VS-shell products such as SSMS,
    # and vswhere's own -latest would then pick SSMS 22 over VS 2026
    $products = 'Community', 'Professional', 'Enterprise' | ForEach-Object { "Microsoft.VisualStudio.Product.$_" }
    # Parse into a variable first: Windows PowerShell 5.1's ConvertFrom-Json emits a JSON array as a
    # single object, so piping it straight on would bind the whole array to $_ once multiple VS are installed
    $found = (& $vswhere -products $products -version '[17.0,)' -format json) -join "`n" | ConvertFrom-Json
    $instances = $found |
        ForEach-Object {
            [PSCustomObject]@{
                DisplayName = $_.displayName
                InstanceId  = $_.instanceId
                Version     = [version]$_.installationVersion
                IDEDir      = Join-Path $_.installationPath "Common7\IDE"
            }
        } |
        Where-Object { Test-Path $_.IDEDir } |
        Sort-Object Version -Descending

    if ($All) { return $instances }
    return $instances | Select-Object -First 1
}

function Test-IsVsix {
    param([String] $Path)

    # A VSIX is a zip archive; anything else (HTML error page, gzip stream) is a failed download
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -lt 4) { return $false }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 2
        [void]$stream.Read($bytes, 0, 2)
        return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) # "PK"
    }
    finally {
        $stream.Dispose()
    }
}

function Get-VsixPackage {
    param(
        [String] $PackageName,
        [String] $DownloadDir)

    $VsixLocation = Join-Path $DownloadDir "$PackageName.vsix"
    $publisher, $extension = $PackageName -split '\.', 2

    # Direct gallery endpoint avoids loading and scraping the marketplace page
    $apiUri = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$extension/latest/vspackage"
    try {
        Write-Host "Downloading $($PackageName)..."
        Invoke-WebRequest -Uri $apiUri -OutFile $VsixLocation -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Host "Gallery API download failed for $($PackageName): $($_.Exception.Message)"
    }

    if (-not (Test-IsVsix $VsixLocation)) {
        # Fallback: scrape the install button from the marketplace page
        try {
            $Uri = "https://marketplace.visualstudio.com/items?itemName=$($PackageName)"
            Write-Host "Falling back to marketplace page $($Uri)"
            $HTML = Invoke-WebRequest -Uri $Uri -UseBasicParsing -SessionVariable session -ErrorAction Stop

            $anchor = $HTML.Links |
            Where-Object { $_.class -eq "install-button-container install-btn" } |
            Select-Object -ExpandProperty href

            if (-not $anchor) {
                Write-Warning "Could not find download anchor tag for $($PackageName), skipping"
                return $null
            }
            Invoke-WebRequest "https://marketplace.visualstudio.com$($anchor)" -OutFile $VsixLocation -WebSession $session -UseBasicParsing -ErrorAction Stop
        }
        catch {
            Write-Warning "Download of $($PackageName) failed: $($_.Exception.Message)"
            return $null
        }
    }

    if (-not (Test-IsVsix $VsixLocation)) {
        Write-Warning "Downloaded file for $($PackageName) is not a valid VSIX, skipping"
        return $null
    }
    return $VsixLocation
}

function Install-VsixBatch {
    param(
        [String]   $InstallerDir,
        [String]   $InstanceId,
        [String[]] $Paths)

    if (-not $Paths) { return }

    # One VSIXInstaller run per package: a per-machine (/a) multi-vsix run goes through the setup engine as a batch,
    # which fails every local marketplace VSIX with "Value cannot be null. Parameter name: uri" (exit 1603)
    Write-Host "************    Installing $($Paths.Count) package(s) with $($InstallerDir)\VSIXInstaller.exe"
    foreach ($path in $Paths) {
        Write-Host "                $path"
        $argumentList = @('/q', '/a', "/instanceIds:$InstanceId", "`"$path`"")
        $process = Start-Process -FilePath "$($InstallerDir)\VSIXInstaller.exe" -ArgumentList $argumentList -Wait -PassThru

        # 0 = success, 1001 = already installed
        if ($process.ExitCode -notin 0, 1001) {
            Write-Warning "VSIXInstaller exited with code $($process.ExitCode) for $(Split-Path $path -Leaf); see %TEMP%\dd_VSIXInstaller_*.log"
        }
        else {
            Write-Host "Installation complete (exit code $($process.ExitCode))"
        }
    }
}

Get-Process devenv -ErrorAction Ignore | Stop-Process -ErrorAction Ignore

$vsExtensions = @(
    'cpmcgrath.Codealignment'
    ,'EWoodruff.VisualStudioSpellCheckerVS2022andLater'
    ,'MadsKristensen.OpeninVisualStudioCode'
    ,'MadsKristensen.TrailingWhitespace64'
    ,'ViktarKarpach.DebugAttachManager2022'
    ,'Zhenkas.LocateInTFS'
)

$vsInstances = @(Get-TargetVSInstances -All:$AllVersions)
if ($vsInstances.Count -eq 0) {
    Write-Warning "No Visual Studio 2022 or later instance found, skipping VS extensions"
}
else {
    $vsInstances | ForEach-Object { Write-Host "Target: $($_.DisplayName) $($_.Version) at $($_.IDEDir)" }
}

$downloadDir = Join-Path $env:TEMP "VsExt-$([guid]::NewGuid())"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

try {
    # Marketplace VSIXs are version independent, so download each one once
    $vsixPaths = @()
    if ($vsInstances.Count -gt 0) {
        foreach ($package in $vsExtensions) {
            $vsixPath = Get-VsixPackage -PackageName $package -DownloadDir $downloadDir
            if ($vsixPath) { $vsixPaths += $vsixPath }
        }
    }

    # The *.17.0.vsix manifests target Version="[17.0,)", so the same packages install into VS 2022 (17) and VS 2026 (18)
    $d365Vsix = @(Get-ChildItem "K:\DeployablePackages" -Include "*.17.0.vsix" -Recurse -ErrorAction Ignore |
        Select-Object -ExpandProperty FullName)

    foreach ($vsInstance in $vsInstances) {
        Write-Host "Installing extensions into $($vsInstance.DisplayName) $($vsInstance.Version)"
        Install-VsixBatch -InstallerDir $vsInstance.IDEDir -InstanceId $vsInstance.InstanceId -Paths ($vsixPaths + $d365Vsix)
    }
}
finally {
    Write-Host "Cleanup..."
    Remove-Item $downloadDir -Recurse -Force -ErrorAction Ignore
}

Write-Host "Installing TrudUtils"

$currentPath = Get-Location
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
$tag = (Invoke-WebRequest -Uri $releases -UseBasicParsing | ConvertFrom-Json)[0].tag_name

$files = @("InstallToVS.exe", "TRUDUtilsD365.dll", "TRUDUtilsD365.pdb")

Write-Host Downloading files
foreach ($file in $files) {
    $download = "https://github.com/$repo/releases/download/$tag/$file"
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

# The installer-level VSIXInstaller handles the legacy (non 17.0) packages
$legacyInstallerDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
$legacyVsix = @(Get-ChildItem "K:\DeployablePackages" -Include "*.vsix" -Exclude "*.17.0.vsix" -Recurse -ErrorAction Ignore |
    Select-Object -ExpandProperty FullName)

if ($legacyVsix.Count -gt 0 -and (Test-Path "$legacyInstallerDir\VSIXInstaller.exe")) {
    foreach ($vsInstance in $vsInstances) {
        Install-VsixBatch -InstallerDir $legacyInstallerDir -InstanceId $vsInstance.InstanceId -Paths $legacyVsix
    }
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
