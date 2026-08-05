<#
.SYNOPSIS
Cleans, generates labels for, compiles and best-practice-checks a single Dynamics 365 Finance &
Operations model.

.DESCRIPTION
The compile recipe used by the orchestrators, in one place. For the model given, it:

  1. Clears the previous build output: stale logs at the model root, built assemblies, metadata
     descriptors and X++ intermediate files under `bin`, and the generated `XppMetadata` tree.
  2. Generates labels.
  3. Compiles with cross-reference generation.
  4. Runs the best-practice check, unless -SkipBestPractice is given.

Both compilation steps are checked for errors via the non-empty error logs left in the model
directory: label errors (`.labelc.err`) print to the console, compiler errors (`.xppc.err.xml`)
open in VS Code. On either failure the script sounds an alert and throws, so a caller looping over
several models stops on the first bad one -- `exit` would only end this script and let the caller
carry on.

Deliberately does nothing environmental: no elevation check, no Defender toggling, no service
stop/start, no `Set-Location`, no pause-for-keypress. Those belong to whoever calls it.

.PARAMETER Model
Name of the D365 model (the package folder name under the packages local directory). Mandatory.

.PARAMETER PackagesLocalDirectory
Root of the packages local directory. Defaults to the D365 environment's bin directory, falling
back to `K:\AosService\PackagesLocalDirectory`. Callers that have already resolved it should pass
it in rather than paying for `Get-D365EnvironmentSettings` per model.

.PARAMETER SkipBestPractice
Skips the best-practice check after a successful compile. Defaults off -- the check is part of the
normal build.

.EXAMPLE
.\Invoke-D365ModelCompile.ps1 -Model "VFF"

.EXAMPLE
.\Invoke-D365ModelCompile.ps1 -Model "VFF" -SkipBestPractice

Clean, labels and compile only.

.EXAMPLE
$Models | ForEach-Object { & "$PSScriptRoot\Invoke-D365ModelCompile.ps1" -Model $_ -PackagesLocalDirectory $PackagesLocalDirectory }

How the orchestrators call it. Wrap the loop in try/catch: a label or compilation error throws.

.NOTES
- Requires d365fo.tools; `code` must be on PATH (VSCode) for the compiler error log to open.
- Must run elevated in practice, since the D365 module directories are not user-writable.
- Services one model only; does not stop/start D365 services or sync the database.
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $Model,

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

if (-not $PackagesLocalDirectory) {
    $D365Environment = Get-D365EnvironmentSettings
    $PackagesLocalDirectory = if ($D365Environment.Common.BinDir) 
        { $D365Environment.Common.BinDir } else { 'K:\AosService\PackagesLocalDirectory' }
}
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
#endregion Functions

$ModelToServe = Get-D365Module $Model
if (-not $ModelToServe) {
    throw "Model $Model not found in $PackagesLocalDirectory"
}

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

Get-D365Module $Model | Invoke-D365ModuleCompile -XRefGeneration -LogPath $PackagesLocalDirectory

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

if ($SkipBestPractice) {
    return
}

Write-Host ""
Write-Host "*** Checking Best Practices for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

Invoke-D365BestPractice -Module $Model -Model $Model -PackagesRoot
Write-Finished $TaskStartTime
