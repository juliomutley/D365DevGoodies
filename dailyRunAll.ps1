<#
.SYNOPSIS
    The nightly full refresh of a D365 F&O development environment: undo ISV changes, get latest,
    compile every model in models.json, sync the database, restart services and refresh entities.

.DESCRIPTION
    The unattended sibling of UpdateDevAll.ps1. It:

      1. Starts a transcript in d:\temp and disables Windows Defender real-time monitoring.
      2. Updates the dbatools / d365fo.tools / d365fo.integrations PowerShell modules.
      3. Kills Visual Studio and stops the D365 environment and IIS Express.
      4. Undoes ISV changes and gets latest from TFVC for every configured model.
      5. Generates labels and compiles each model, with cross-reference generation and a
         best-practice check, via Invoke-D365ModelCompile.ps1.
      6. Runs a full database synchronisation via syncDB.ps1, which raises SQL Server max memory
         to 70% of RAM and MAXDOP to 0 for the duration and puts them back afterwards.
      7. Enables the D365 Windows services and starts the environment.
      8. Opens the environment on the Feature Management page.
      9. Refreshes the OData/DMF entity list, if credentials were supplied.
     10. Runs the sibling repo's updateApps.ps1.

    Model lists come from models.json via Get-ModelConfig.ps1 -- never hardcode them here.

    Unlike UpdateDevAll.ps1 this script never waits for a keypress: it is built to run scheduled
    and unattended, so its 'pause' helper only prints a banner. It also does not call
    set-Cypher.ps1, which can reboot the machine.

.PARAMETER tenantId
    Microsoft Entra tenant id used for the OData/DMF entity refresh. The refresh is skipped
    unless tenantId, clientId and secretKey are all supplied.

.PARAMETER clientId
    Application (client) id of the Entra app used for the entity refresh. Its row in
    SYSAADCLIENTTABLE is deleted and re-imported against the 'admin' user.

.PARAMETER secretKey
    Client secret for the Entra app above.

.PARAMETER ResetUserData
    Truncates the disposable user-data tables in the local AxDb before compiling, via
    Reset-D365UserData.ps1, clearing stale personalisation and last-value data that can survive a
    metadata change.

    Defaults off because 'truncate table' is unrecoverable; ask for it when a form starts
    rendering oddly after a build.

.EXAMPLE
    .\dailyRunAll.ps1

    Full refresh: TF undo, get latest, compile all, sync the database. No entity refresh.

.EXAMPLE
    .\dailyRunAll.ps1 -ResetUserData

    Same, but purge saved form setups and personalisations first.

.EXAMPLE
    .\dailyRunAll.ps1 -tenantId $tenant -clientId $client -secretKey $secret

    Full refresh, then re-import the Entra application and refresh the DMF entity list.

.NOTES
    Requires: d365fo.tools, d365fo.integrations, dbatools, VSSetup (installed on demand); 'code'
    on PATH for the compiler error log, and TF.exe from a VS2022 installation.

    enableServices.ps1 and updateApps.ps1 come from the d365-resources repo, expected alongside
    this one at ..\d365-resources\365_PowerShell.

    Must run elevated -- Set-MpPreference and the SQL Server instance settings both need it.

    Long-running: a full compile of several models plus a database sync is measured in hours.
    Transcript at d:\temp\updateDevLog<yyyyMMdd>.log.

    Real-time monitoring is disabled for the run, since on-access scanning slows compilation
    considerably. Note that syncDB.ps1 re-enables it in its own finally block, so everything after
    the sync (entity refresh, updateApps.ps1) proceeds with monitoring on -- harmless, as
    compilation is long finished by then.

    The compile and the sync are delegated to Invoke-D365ModelCompile.ps1 and syncDB.ps1 -- change
    the recipe there, not here.
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [String] $tenantId,

    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [String] $clientId,

    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [string] $secretKey,

    [Parameter(Mandatory=$false)]
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

if(-not(Test-Path "d:\temp"))
{
    mkdir "d:\temp"
}
$execDate = (Get-Date).tostring('yyyyMMdd')
Start-Transcript "d:\temp\updateDevLog$execDate.log" -Force

Set-MpPreference -DisableRealtimeMonitoring $true

#region install modules
$Module2Service = $('dbatools',
    'd365fo.tools',
    'd365fo.integrations')

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

[bool] $vsSetupExists = $null -ne (Get-Command Get-VSSetupInstance -ErrorAction SilentlyContinue)
if (!$vsSetupExists)
{
    Write-Verbose "Installing the VSSetup module..."
    Install-Module VSSetup -Scope CurrentUser -Force
}
# Select Visual Studio 2022 specifically (version 17.x)
[string] $visualStudioInstallationPath = (Get-VSSetupInstance | Where-Object { $_.InstallationVersion -like '17.*' } | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

$tfExe = (Get-ChildItem $visualStudioInstallationPath -Recurse -Filter "TF.exe" | Select-Object -First 1).FullName
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
    Write-Host ""
    Write-Host "*** $message ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
    Write-Host
}

#endregion Functions

#Region Main
stop-process -name devenv -ErrorAction Ignore

# Opt-in: the table list lives in Reset-D365UserData.ps1, shared with the other orchestrators
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
}

Finished $TaskStartTime

# Recipe lives in Add-D365SourceControl.ps1 -- change it there, not here.
& "$PSScriptRoot\Add-D365SourceControl.ps1" -Models $Models2Compile -PackagesLocalDirectory $PackagesLocalDirectory -TfExePath $tfExe

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
    Stop-Transcript
    exit 1
}

Write-Host ""
Write-Host "*** Finished servicing all models. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

ElapsedTime $TaskStartTime
#end region

#region sync db
Write-Host ""
Write-Host "*** Syncronizing database... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

# syncDB.ps1 owns the whole recipe: SQL max memory and MAXDOP up for the sync and back down
# afterwards, in a finally so an interrupted sync still hands the machine back.
& "$PSScriptRoot\syncDB.ps1"

Write-Host ""
Write-Host "*** Starting services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

&"$PSScriptRoot\enableServices.ps1"
Start-D365Environment

Finished $TaskStartTime

Write-Host ""
Write-Host "*** All done! ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

#end region

ElapsedTime $ExecutionStartTime
$MenuItem = 'FeatureManagementCheckForUpdates'

$D365Url = Get-D365Url
$D365Url = $D365Url.Url
Write-Host "$D365Url/?mi=$MenuItem"

Set-Location $currentDirectory

Start-Process "$D365Url/?mi=$MenuItem"

# Refresh data entities
if (($tenantId -eq $null -or $tenantId -eq "") `
    -or ($clientId -eq $null -or $clientId -eq "") `
    -or ($secretKey -eq $null -or $secretKey -eq "")) {
    # Do nothing
}    
else {
    # Update Microsoft Entra application    
    $appName = "Automation"
    $adminUser = "admin"

    $deleteAppSql = "DELETE FROM [dbo].[SYSAADCLIENTTABLE] WHERE AADCLIENTID = '$clientId'"
    Invoke-DbaQuery -Query $deleteAppSql -SqlInstance "." -Database "AxDb"

    Import-D365AadApplication `
        -Name $appName `
        -UserId $adminUser `
        -ClientId $clientId   
    
    # Set default Odata configuration
    $odataConfigName = "D365EntityRefresh"

    Add-D365ODataConfig `
        -Name $odataConfigName `
        -Tenant $tenantID `
        -Url $D365Url `
        -ClientId $clientId `
        -ClientSecret $secretKey `
        -Force

    Set-D365ActiveODataConfig -Name $odataConfigName

    # Initiaze Dmf
    $token = Get-D365ODataToken    

    Write-Host "Refresh entity list"
    Invoke-D365DmfInit -Verbose -Token $token -EnableException $true
}

#endregion Refresh data entities

#Region SO maintenance
& "$PSScriptRoot\updateApps.ps1"
#endregion SO maintenance

Set-MpPreference -DisableRealtimeMonitoring $false

Stop-Transcript
exit