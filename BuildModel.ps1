<#
.SYNOPSIS
Cleans, generates labels for, and compiles a single Dynamics 365 Finance & Operations model.

.DESCRIPTION
Clears the model's previous build output (assemblies, metadata, X++ intermediate files), generates
labels, then compiles with cross-reference generation. Windows Defender real-time monitoring is
disabled during the run and re-enabled at the end, since on-access scanning slows compilation.

Both steps are checked for errors via the non-empty error logs left in the model directory: label
errors (`.labelc.err`) print to the console, compiler errors (`.xppc.err.xml`) open in VS Code. On
either failure the script sounds an alert, waits for a keypress and exits; monitoring is restored on
the way out by a `finally` block, so a failed build does not leave the machine unprotected.

.PARAMETER Model
Name of the D365 model to service. Mandatory.

.PARAMETER ResetUserData
Truncates the disposable user-data tables (`formRunConfiguration`, `syslastvalue`,
`sysPersonalization`) in the local `AxDb` before compiling, clearing stale personalization and
last-value data that can survive a metadata change.

.EXAMPLE
.\BuildModel.ps1 -Model "VFF"

.EXAMPLE
.\BuildModel.ps1 -Model "VFF" -ResetUserData

.NOTES
- Requires d365fo.tools, plus SqlServer when -ResetUserData is used; `code` must be on PATH (VSCode).
- Must run elevated (`Set-MpPreference` needs administrator rights).
- Packages local directory comes from the D365 environment settings, falling back to
  `K:\AosService\PackagesLocalDirectory`. SQL targets instance `.`, database `AxDb`.
- Services one model only; does not stop/start D365 services or sync the database.

#>

param(
    [Parameter(Mandatory = $true)]
    [string] $Model,

    [Parameter(Mandatory = $false)]
    [switch] $ResetUserData
)

# Bail out before touching the environment rather than failing mid-build
$CurrentPrincipal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "*** This script must run elevated. Re-run it as administrator. ***" -ForegroundColor White -BackgroundColor Red
    Write-Host ""
    exit 1
}

#Region Variables
$Models2Compile = @($Model)

$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$ErrorFGColor = "White"
$ErrorBGColor = "Red"
$FinishedFGColor = "Green"
$D365Environment = Get-D365EnvironmentSettings
$ExecutionStartTime = $(Get-Date)
$PackagesLocalDirectory = if ($D365Environment.Common.BinDir) { $D365Environment.Common.BinDir } else { 'K:\AosService\PackagesLocalDirectory' }

#endregion variables

#region Functions
function Write-ElapsedTime($TaskStartTime) {
    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}

function Write-Finished($StartTime) {
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    Write-ElapsedTime $StartTime
}

# Waits for acknowledgement: a message box under ISE, a keypress otherwise
function Invoke-Pause ($message) {
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

function Invoke-CompileModel($Model) {
    Write-Host ""
    Write-Host "*** Servicing model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    # Clear stale logs left at the model root by previous runs
    Remove-Item "$PackagesLocalDirectory\$Model\*.*" -ErrorAction Ignore

    # Remove previously built assemblies, metadata descriptors and X++ intermediate files
    Get-ChildItem "$PackagesLocalDirectory\$Model\bin" `
        -Include "Dynamics*.*", "$Model*.MD", "*.xpp" -Recurse | `
        Remove-Item -Force -Recurse -ErrorAction Ignore

    # Remove generated X++ metadata so the compiler regenerates it from source
    Get-ChildItem "$PackagesLocalDirectory\$Model\XppMetadata" -Recurse `
        | Remove-Item -Force -Recurse -ErrorAction Ignore

    Write-Host ""
    Write-Host "*** Building labels for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    Invoke-D365ModuleLabelGeneration -Module $Model -LogPath $PackagesLocalDirectory

    # A non-empty label error log means label compilation failed; show it and stop
    if ((Test-Path -Path "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err" -PathType Leaf) -and `
        ((Get-Item "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err").Length -gt 0)) 
    {
        Write-Host ""
        Write-Host "*** Label compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Get-Content -Path "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err"
        [system.media.systemsounds]::Hand.play()
        Invoke-Pause("Press any key to continue...")
        exit
    }

    Write-Host ""
    Write-Host "*** Building model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    Invoke-D365ModuleCompile -Module $Model -XRefGeneration -LogPath $PackagesLocalDirectory

    Write-Finished $TaskStartTime

    # A non-empty X++ error log means compilation failed; open it in VS Code and stop
    $ErrorLogFile ="$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.xppc.err.xml"
    if ((Test-Path -Path $ErrorLogFile -PathType Leaf) -and `
        ((Get-Item -Path $ErrorLogFile).Length -gt 0))
    {
        Write-Host ""
        Write-Host "*** Compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        code $ErrorLogFile
        [system.media.systemsounds]::Hand.play()
        Invoke-Pause("Press any key to continue...")
        exit
    }

}

function Invoke-ResetUserData {
    Write-Host ""
    Write-Host "*** Purging disposable user data... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    # Personalization and last-value data that can break after a metadata change
    $DisposableTables = @(
        "formRunConfiguration"
        ,"syslastvalue"
        ,"sysPersonalization"
    )

    $DisposableTables | ForEach-Object {
        Write-Host "purging $_"
        $sql = "truncate table $_"
        Invoke-Sqlcmd -Query $sql -ServerInstance "." -Database "AxDb" -TrustServerCertificate
    }
}
#EndRegion

# On-access scanning slows compilation considerably; the finally block below always restores it,
# including on the early exits taken when label or X++ compilation fails
Set-MpPreference -DisableRealtimeMonitoring $true

try {
    if ($ResetUserData) {
        Invoke-ResetUserData
    }

    $TaskStartTime = $(Get-Date)

    $Models2Compile | ForEach-Object { Invoke-CompileModel $_ }

    Write-Host ""
    Write-Host "*** Finished servicing $Model. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    Write-ElapsedTime $ExecutionStartTime
}
finally {
    # Re-enable on-access scanning and signal completion audibly
    Set-MpPreference -DisableRealtimeMonitoring $false
    [system.media.systemsounds]::Hand.play()
}