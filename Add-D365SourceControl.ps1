<#
.SYNOPSIS
    Adds untracked xml files under each configured model to TFVC source control.

.DESCRIPTION
    For every model folder passed in (or every ModelsToBuild entry from models.json, by
    default), reads the model's Descriptor\*.xml to find its inner model name, changes into
    that model's folder, and runs 'tf add ./*.xml /recursive' there. This picks up new or
    changed xml files -- typically label or metadata files a compile has just produced or
    touched -- that TFVC does not yet know about.

    A model whose Descriptor\*.xml is not found yet (not gotten from source control, or not
    built) is skipped silently -- this mirrors the behaviour of the inline loop this script
    replaced in UpdateDevAll.ps1 and dailyRunAll.ps1.

    This is a recipe script in the same vein as Invoke-D365ModelCompile.ps1 and syncDB.ps1:
    change the tf-add recipe here, not in the orchestrators that call it.

.PARAMETER Models
    Model folder names under PackagesLocalDirectory to add. Defaults to ModelsToBuild from
    models.json via Get-ModelConfig.ps1.

.PARAMETER PackagesLocalDirectory
    Root folder containing the model folders. Defaults to the current D365 environment's
    Common.BinDir via Get-D365EnvironmentSettings.

.PARAMETER TfExePath
    Path to TF.exe. Defaults to locating it under the VS2022 installation via VSSetup,
    installing that module on demand. Locating TF.exe this way means a recursive scan of the
    whole VS install tree, so callers that have already resolved it (both orchestrators do,
    for their own tf undo/get calls) should pass it in here rather than pay for a second scan.

.EXAMPLE
    .\Add-D365SourceControl.ps1

    Add untracked xml files for every ModelsToBuild model in models.json.

.EXAMPLE
    .\Add-D365SourceControl.ps1 -Models 'FleetManagement' -TfExePath $tfExe

    Add untracked xml files for a single model, using an already-resolved TF.exe.

.NOTES
    Requires: TF.exe from a VS2022 installation (VSSetup module, installed on demand, to
    locate it, unless -TfExePath is supplied).
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]] $Models,

    [Parameter(Mandatory = $false)]
    [string] $PackagesLocalDirectory,

    [Parameter(Mandatory = $false)]
    [string] $TfExePath
)

#region variables
$ErrorBGColor = "Red"
$ErrorFGColor = "White"
$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$FinishedFGColor = "Green"
$currentDirectory = Get-Location

if (-not $Models) {
    $Models = (& "$PSScriptRoot\Get-ModelConfig.ps1").ModelsToBuild
}

if (-not $PackagesLocalDirectory) {
    $PackagesLocalDirectory = (Get-D365EnvironmentSettings).Common.BinDir
}

if (-not $TfExePath) {
    [bool] $vsSetupExists = $null -ne (Get-Command Get-VSSetupInstance -ErrorAction SilentlyContinue)
    if (!$vsSetupExists)
    {
        Write-Verbose "Installing the VSSetup module..."
        Install-Module VSSetup -Scope CurrentUser -Force
    }
    # Select Visual Studio 2022 specifically (version 17.x)
    [string] $visualStudioInstallationPath = (Get-VSSetupInstance | Where-Object { $_.InstallationVersion -like '17.*' } | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

    $TfExePath = (Get-ChildItem $visualStudioInstallationPath -Recurse -Filter "TF.exe" | Select-Object -First 1).FullName
}
#endregion variables

#region Functions
function ElapsedTime($TaskStartTime) {
    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}

function Finished($StartTime) {
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    ElapsedTime $StartTime
}
#endregion Functions

#Region Main
Write-Host ""
Write-Host "*** Adding untracked files to source control... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

try
{
    $Models | ForEach-Object {
        if (Test-Path "$PackagesLocalDirectory\$_\Descriptor\*.xml" -PathType Leaf)
        {
            [xml]$XmlDocument = Get-Content -Path "$PackagesLocalDirectory\$_\Descriptor\*.xml"

            $ModelName = $XmlDocument.AxModelInfo.Name

            Set-Location "$PackagesLocalDirectory\$_\$ModelName"
            $TFArgs = @('add', './*.xml', '/recursive')
            &$TfExePath $TFArgs
        }
    }
}
finally
{
    Set-Location $currentDirectory
}

Finished $TaskStartTime
#end region
