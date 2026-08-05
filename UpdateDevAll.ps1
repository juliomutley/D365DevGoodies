<#
.SYNOPSIS
    Refreshes a D365 F&O development environment: undo ISV changes, get latest, compile every
    model in models.json, sync the database, restart services.

.DESCRIPTION
    The full-refresh orchestrator. In its default form it:

      1. Updates the dbatools / d365fo.tools PowerShell modules.
      2. Kills Visual Studio and stops the D365 environment and IIS Express.
      3. Undoes ISV changes and gets latest from TFVC for every configured model.
      4. Generates labels and compiles each model, with cross-reference generation and a
         best-practice check, via Invoke-D365ModelCompile.ps1.
      5. Starts the D365 services back up.
      6. Runs a full database synchronisation via syncDB.ps1, which raises SQL Server max memory
         to 70% of RAM and MAXDOP to 0 for the duration and puts them back afterwards.
      7. Opens the environment on the Feature Management page.

    Model lists come from models.json via Get-ModelConfig.ps1 -- never hardcode them here.
    Windows Defender real-time monitoring is disabled for the run, since on-access scanning slows
    compilation considerably. Note that syncDB.ps1 re-enables it in its own finally block, so the
    tail of a full run (opening the browser) proceeds with monitoring on -- harmless, as
    compilation is long finished by then.

.PARAMETER NoSync
    Skips the entire TFVC section (both the undo of ISV changes and the get-latest) and the
    database synchronisation, leaving a clean-and-compile of the configured models. Services are
    still stopped and restarted, so the result is a usable environment.

    Defaults off because the normal use of this script is the full refresh; -NoSync is the cheap
    path for recompiling a local change you have not checked in, and it supersedes the old
    UpdateDevNoSync.ps1. Note that ModelsToUndoChanges is unused in this mode.

.PARAMETER ResetUserData
    Truncates the disposable user-data tables in the local AxDb before compiling, via
    Reset-D365UserData.ps1, clearing stale personalisation and last-value data that can survive a
    metadata change.

    Defaults off because 'truncate table' is unrecoverable; ask for it when a form starts
    rendering oddly after a build.

.EXAMPLE
    .\UpdateDevAll.ps1

    Full refresh: TF undo, get latest, compile all, sync the database.

.EXAMPLE
    .\UpdateDevAll.ps1 -NoSync

    Compile the configured models only -- no source control, no database sync.

.EXAMPLE
    .\UpdateDevAll.ps1 -NoSync -ResetUserData

    Same, but purge saved form setups and personalisations first.

.NOTES
    Requires: d365fo.tools, dbatools, VSSetup (installed on demand); 'code' on PATH for the
    compiler error log, and TF.exe from a VS2022 installation unless -NoSync is used.

    Must run elevated -- Set-MpPreference and the SQL Server instance settings both need it.

    Long-running: a full compile of several models plus a database sync is measured in hours.
    Compilation or label errors stop the script and wait for a keypress; the error log opens in
    VS Code.

    The compile and the sync are delegated to Invoke-D365ModelCompile.ps1 and syncDB.ps1 -- change
    the recipe there, not here.
#>
param(
    [Parameter(Mandatory = $false)]
    [switch] $NoSync,

    [Parameter(Mandatory = $false)]
    [switch] $ResetUserData
)

# Bail out before touching the environment rather than failing mid-run
$CurrentPrincipal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "*** This script must run elevated. Re-run it as administrator. ***" -ForegroundColor White -BackgroundColor Red
    Write-Host ""
    exit 1
}

#region install modules

Set-MpPreference -DisableRealtimeMonitoring $true

&$PSScriptRoot\set-Cypher.ps1

$Module2Service = $('dbatools',
    'd365fo.tools')

$Module2Service | ForEach-Object {
    if (Get-Module -ListAvailable -Name $_) {
        Write-Host "Updating powershell module" $_
        Update-Module -Name $_ -Force
    } 
    else {
        Write-Host "Installing powershell module" $_
        Install-Module -Name $_ -SkipPublisherCheck -Scope AllUsers
    }
    Import-Module $_
}
#endregion

#region models
$ModelConfig        = & "$PSScriptRoot\Get-ModelConfig.ps1"
$Models2Compile     = $ModelConfig.ModelsToBuild
$Models2UndoChanges = $ModelConfig.ModelsToUndoChanges
#endregion models

#region variables
$ErrorBGColor = "Red"
$ErrorFGColor = "White"
$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$FinishedFGColor = "Green"
$D365Environment = Get-D365EnvironmentSettings
$currentDirectory = Get-Location
$ExecutionStartTime = $(Get-Date)
$PackagesLocalDirectory = $D365Environment.Common.BinDir

# Locating TF.exe means a recursive scan of the whole VS install tree, so only pay for it when
# there is actually a TFVC command to run.
if (-not $NoSync)
{
    [bool] $vsSetupExists = $null -ne (Get-Command Get-VSSetupInstance -ErrorAction SilentlyContinue)
    if (!$vsSetupExists)
    {
        Write-Verbose "Installing the VSSetup module..."
        Install-Module VSSetup -Scope CurrentUser -Force
    }
    # Select Visual Studio 2022 specifically (version 17.x)
    [string] $visualStudioInstallationPath = (Get-VSSetupInstance | Where-Object { $_.InstallationVersion -like '17.*' } | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

    $tfExe = (Get-ChildItem $visualStudioInstallationPath -Recurse -Filter "TF.exe" | Select-Object -First 1).FullName
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

function pause ($message) {
    # Check if running Powershell ISE
    if ($psISE) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("$message")
    }
    else {
        Write-Host "$message" -ForegroundColor Yellow
        $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

#endregion Functions

#Region Main
stop-process -name devenv -ErrorAction Ignore

# Opt-in: the table list lives in Reset-D365UserData.ps1, shared with BuildModel.ps1
if ($ResetUserData) {
    & "$PSScriptRoot\Reset-D365UserData.ps1"
}

Write-Host ""
Write-Host "*** Stopping services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)
Stop-D365Environment -Kill

Stop-Process -Name "iisexpress" -ErrorAction SilentlyContinue

Finished $TaskStartTime

#clear IIS logs
Get-ChildItem -File "C:\inetpub\logs\LogFiles" -Recurse | Where-Object {$_.CreationTime -lt ((Get-Date).AddDays(-7).Date)} | Remove-Item

#region source control
if ($NoSync)
{
    Write-Host ""
    Write-Host "*** -NoSync: skipping undo and get latest. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""
}
else
{
    Write-Host ""
    Write-Host "*** Undoing ISV changes... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    $Models2UndoChanges | ForEach-Object {
        $TFArgs = @('undo', '*', '/recursive', '/noprompt')
        if(!(Test-Path "$packagesLocalDirectory\$_"))
        {
            Write-Host ""
            Write-Host "*** $_ not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
            Write-Host ""
            Pause("Press any key to continue...")
            Set-Location $currentDirectory
            exit
        }
        Set-Location "$packagesLocalDirectory\$_"
        &$tfExe $TFArgs
        if($LASTEXITCODE -gt 1)
        {
            Write-Host ""
            Write-Host "*** $_ failed to undo changes, aborting... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
            Write-Host ""
            Pause("Press any key to continue...")
            Set-Location $currentDirectory
            exit
        }
    }

    Finished $TaskStartTime

    Write-Host ""
    Write-Host "*** Getting latest changes from Azure DevOps... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    $Models2Compile | ForEach-Object {
        $TFArgs = @('get', '/recursive')
        if(!(Test-Path "$packagesLocalDirectory\$_"))
        {
            Write-Host ""
            Write-Host "*** $_ not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
            Write-Host ""
            Set-Location $currentDirectory
            Pause("Press any key to continue...")
            exit
        }
        Set-Location "$packagesLocalDirectory\$_"
        &$tfExe $TFArgs
        if($LASTEXITCODE -gt 1)
        {
            Write-Host ""
            Write-Host "*** $_ failed to get latest changes, aborting... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
            Write-Host ""
            Pause("Press any key to continue...")
            Set-Location $currentDirectory
            exit
        }

        if (Test-Path "$PackagesLocalDirectory\$_\Descriptor\*.xml" -PathType Leaf)
        {
            [xml]$XmlDocument = Get-Content -Path "$PackagesLocalDirectory\$_\Descriptor\*.xml"

            $ModelName = $XmlDocument.AxModelInfo.Name

            Set-Location "$packagesLocalDirectory\$_\$ModelName"
            $TFArgs = @('add', './*.xml', '/recursive')
            &$tfExe $TFArgs
        }
    }

    Finished $TaskStartTime
}
#endregion source control

$TaskStartTime = $(Get-Date)

# Invoke-D365ModelCompile.ps1 throws on a label or compilation error rather than exiting, since an
# exit in a child script would only end the child and let this one run on into the sync.
# -DisableDefender:$false because real-time monitoring is already off for the whole run (see above);
# letting the child restore it would leave every model after the first scanning on access.
try
{
    $Models2Compile | ForEach-Object {
        & "$PSScriptRoot\Invoke-D365ModelCompile.ps1" -Model $_ -DisableDefender:$false
    }
}
catch
{
    Write-Host ""
    Write-Host "*** $($_.Exception.Message) ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
    Write-Host ""
    Set-Location $currentDirectory
    Set-MpPreference -DisableRealtimeMonitoring $false
    Pause("Press any key to continue...")
    exit 1
}

Write-Host ""
Write-Host "*** Finished servicing all models. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

ElapsedTime $TaskStartTime

Write-Host ""
Write-Host "*** Starting services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

# Started here rather than after the sync so that -NoSync still leaves a usable environment
Start-D365Environment

ElapsedTime $TaskStartTime
#end region

#region sync db
if ($NoSync)
{
    Write-Host ""
    Write-Host "*** -NoSync: skipping database synchronisation. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""
}
else
{
    Write-Host ""
    Write-Host "*** Syncronizing database... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    # syncDB.ps1 owns the whole recipe: SQL max memory and MAXDOP up for the sync and back down
    # afterwards, in a finally so an interrupted sync still hands the machine back.
    & "$PSScriptRoot\syncDB.ps1"

    Finished $TaskStartTime
}

Write-Host ""
Write-Host "*** All done! ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""
#end region

ElapsedTime $ExecutionStartTime
[system.media.systemsounds]::Hand.play()
$MenuItem = 'FeatureManagementCheckForUpdates'

$D365Url = Get-D365Url
$D365Url = $D365Url.Url
Write-Host "$D365Url/?mi=$MenuItem"

Set-Location $currentDirectory

Start-Process "$D365Url/?mi=$MenuItem"

Set-MpPreference -DisableRealtimeMonitoring $false
Pause("Press any key to continue...")