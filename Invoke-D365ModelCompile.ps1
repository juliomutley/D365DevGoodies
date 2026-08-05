<#
.SYNOPSIS
Cleans, generates labels for, compiles and best-practice-checks a single Dynamics 365 Finance &
Operations model.

.DESCRIPTION
The compile recipe used by the orchestrators, in one place. For the model given, it:

  1. Truncates the disposable user-data tables, if -ResetUserData is given.
  2. Clears the previous build output: stale logs at the model root, built assemblies, metadata
     descriptors and X++ intermediate files under `bin`, and the generated `XppMetadata` tree.
  3. Generates labels.
  4. Compiles with cross-reference generation.
  5. Runs the best-practice check, unless -SkipBestPractice is given.

Both compilation steps are checked for errors via the non-empty error logs left in the model
directory: label errors (`.labelc.err`) print to the console, compiler errors (`.xppc.err.xml`)
open in VS Code. On either failure the script sounds an alert and throws, so a caller looping over
several models stops on the first bad one -- `exit` would only end this script and let the caller
carry on.

Windows Defender real-time monitoring is disabled for the duration by default, since on-access
scanning slows compilation considerably, and restored in a `finally` -- so a failed build does not
leave the machine unprotected. Callers that already toggle it around a whole run should pass
-DisableDefender:$false rather than have it re-enabled after each model.

Beyond that toggle and the optional user-data reset it does nothing environmental: no elevation
check, no service stop/start, no `Set-Location`, no pause-for-keypress. Those belong to whoever
calls it.

.PARAMETER Model
Name of the D365 model (the package folder name under the packages local directory). Mandatory.

.PARAMETER PackagesLocalDirectory
Root of the packages local directory. Defaults to the D365 environment's bin directory, falling
back to `K:\AosService\PackagesLocalDirectory`. Callers that have already resolved it should pass
it in rather than paying for `Get-D365EnvironmentSettings` per model.

.PARAMETER ResetUserData
Truncates the disposable user-data tables (`formRunConfiguration`, `SysLastValue`, `SysUserLog`,
`sysPersonalization`) in the local `AxDb` before compiling, clearing stale personalization and
last-value data that can survive a metadata change. Delegates to `Reset-D365UserData.ps1`, which
owns the table list.

Defaults off because `truncate table` is unrecoverable. Note it runs per model: a caller looping
over several models should call `Reset-D365UserData.ps1` once itself instead of passing this.

.PARAMETER DisableDefender
Disables Windows Defender real-time monitoring for the duration of the compile and restores it on
the way out, including on the throw taken when compilation fails. Defaults on -- on-access scanning
costs more than the toggle.

Pass -DisableDefender:$false when the caller already disabled monitoring around a longer run;
otherwise this script's `finally` would switch scanning back on for whatever the caller does next.
Needs administrator rights when on.

.PARAMETER ShowElapsedTime
Prints the elapsed time of the compile, the best-practice check and the model as a whole. Defaults
on. Pass -ShowElapsedTime:$false to keep the output to progress banners only.

.PARAMETER SkipBestPractice
Skips the best-practice check after a successful compile. Defaults off -- the check is part of the
normal build.

.EXAMPLE
.\Invoke-D365ModelCompile.ps1 -Model "VFF"

.EXAMPLE
.\Invoke-D365ModelCompile.ps1 -Model "VFF" -SkipBestPractice

Clean, labels and compile only.

.EXAMPLE
.\Invoke-D365ModelCompile.ps1 -Model "VFF" -ResetUserData

Purge saved form setups and personalisations first.

.EXAMPLE
$Models | ForEach-Object { & "$PSScriptRoot\Invoke-D365ModelCompile.ps1" -Model $_ -PackagesLocalDirectory $PackagesLocalDirectory -DisableDefender:$false }

How the orchestrators call it: they toggle Defender once around the whole run, so they opt out of
the per-model toggle. Wrap the loop in try/catch -- a label or compilation error throws.

.NOTES
- Requires d365fo.tools, plus dbatools when -ResetUserData is used; `code` must be on PATH (VSCode)
  for the compiler error log to open.
- Must run elevated in practice, since the D365 module directories are not user-writable, and
  -DisableDefender needs administrator rights.
- Services one model only; does not stop/start D365 services or sync the database.
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $Model,

    [Parameter(Mandatory = $false)]
    [switch] $ResetUserData,

    [Parameter(Mandatory = $false)]
    [switch] $DisableDefender = $true,

    [Parameter(Mandatory = $false)]
    [switch] $ShowElapsedTime = $true,

    [Parameter(Mandatory = $false)]
    [switch] $SkipBestPractice,

    [Parameter(Mandatory = $false)]
    [string] $PackagesLocalDirectory
)

#region variables
$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$ErrorFGColor = "White"
$ErrorBGColor = "Red"
$FinishedFGColor = "Green"
$ExecutionStartTime = $(Get-Date)

if (-not $PackagesLocalDirectory) {
    $D365Environment = Get-D365EnvironmentSettings
    $PackagesLocalDirectory = if ($D365Environment.Common.BinDir)
        { $D365Environment.Common.BinDir } else { 'K:\AosService\PackagesLocalDirectory' }
}
#endregion variables

#region Functions
function Write-ElapsedTime($TaskStartTime) {
    # -ShowElapsedTime is honoured here rather than at each call site
    if (-not $ShowElapsedTime) { return }

    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}

function Write-Finished($StartTime) {
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    Write-ElapsedTime $StartTime
}
#endregion Functions

$ModelToServe = Get-D365Model $Model
if (-not $ModelToServe) {
    throw "Model $Model not found in $PackagesLocalDirectory"
}

# Opt-in, and after the existence check: a mistyped model name must not cost anyone their
# personalisations. The table list lives in Reset-D365UserData.ps1.
if ($ResetUserData) {
    & "$PSScriptRoot\Reset-D365UserData.ps1"
}

# On-access scanning slows compilation considerably; the finally block below always restores it,
# including on the throws taken when label or X++ compilation fails
if ($DisableDefender) {
    Set-MpPreference -DisableRealtimeMonitoring $true
}

try {
    Write-Host ""
    Write-Host "*** Servicing model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    # Clear stale logs left at the model root by previous runs
    Remove-Item "$PackagesLocalDirectory\$Model\*.*" -ErrorAction Ignore

    # Remove previously built assemblies, metadata descriptors and X++ intermediate files
    Get-ChildItem "$PackagesLocalDirectory\$Model\bin" `
        -Include "Dynamics*.*", "$Model*.MD", "*.xpp" -Recurse | Remove-Item -Force -Recurse -ErrorAction Ignore

    # Remove generated X++ metadata so the compiler regenerates it from source
    Get-ChildItem "$PackagesLocalDirectory\$Model\XppMetadata" -Recurse | Remove-Item -Force -Recurse -ErrorAction Ignore

    Write-Host ""
    Write-Host "*** Building labels for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    Invoke-D365ModuleLabelGeneration -Module $Model -LogPath $PackagesLocalDirectory

    # A non-empty label error log means label compilation failed; show it and throw
    $LabelErrorLogFile = "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err"
    if ((Test-Path -Path $LabelErrorLogFile -PathType Leaf) -and `
        ((Get-Item -Path $LabelErrorLogFile).Length -gt 0))
    {
        Write-Host ""
        Write-Host "*** Label compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Get-Content -Path $LabelErrorLogFile
        [system.media.systemsounds]::Hand.play()
        throw "Label compilation error on model $Model, see $LabelErrorLogFile"
    }

    Write-Host ""
    Write-Host "*** Building model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    Get-D365Model $Model | Invoke-D365ModuleCompile -XRefGeneration -LogPath $PackagesLocalDirectory -Verbose:$false

    Write-Finished $TaskStartTime

    # A non-empty X++ error log means compilation failed; open it in VS Code and throw
    $ErrorLogFile = "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.xppc.err.xml"
    if ((Test-Path -Path $ErrorLogFile -PathType Leaf) -and `
        ((Get-Item -Path $ErrorLogFile).Length -gt 0))
    {
        Write-Host ""
        Write-Host "*** Compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        code $ErrorLogFile
        [system.media.systemsounds]::Hand.play()
        throw "Compilation error on model $Model, see $ErrorLogFile"
    }

    # Guarded rather than an early return, so the total below is reported either way
    if (-not $SkipBestPractice) {
        Write-Host ""
        Write-Host "*** Checking Best Practices for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
        Write-Host ""

        $TaskStartTime = $(Get-Date)

        Invoke-D365BestPractice -Module $Model -Model $Model -PackagesRoot -Verbose:$false
        Write-Finished $TaskStartTime
    }

    Write-ElapsedTime $ExecutionStartTime
}
finally {
    # Restore on-access scanning, including on the throws above
    if ($DisableDefender) {
        Set-MpPreference -DisableRealtimeMonitoring $false
    }
}
