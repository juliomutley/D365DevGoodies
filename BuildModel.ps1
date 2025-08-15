Set-MpPreference -DisableRealtimeMonitoring $true
#Region Variables
$Models2Compile = $(
    'model'
)

$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$ErrorFGColor = "White"
$ErrorBGColor = "Red"
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
[string] $visualStudioInstallationPath = (Get-VSSetupInstance | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

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

    Remove-Item "$PackagesLocalDirectory\$Model\*.*" -ErrorAction Ignore

    Get-ChildItem "$PackagesLocalDirectory\$Model\bin" `
        -Include "Dynamics*.*", "$Model*.MD", "*.xpp" -Recurse | Remove-Item -Force -Recurse -ErrorAction Ignore

    Get-ChildItem "$PackagesLocalDirectory\$Model\XppMetadata"  -Recurse | Remove-Item -Force -Recurse -ErrorAction Ignore

    Write-Host ""
    Write-Host "*** Building labels for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    Invoke-D365ModuleLabelGeneration -Module $Model -LogPath $PackagesLocalDirectory

    if ((Test-Path -Path "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err" -PathType Leaf) -and `
        ((Get-Item "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err").Length -gt 0)) 
    {
        Write-Host ""
        Write-Host "*** Label compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Get-Content -Path "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.labelc.err"
        [system.media.systemsounds]::Hand.play()
        Set-Location $currentDirectory
        Pause("Press any key to continue...")
        exit
    }

    Write-Host ""
    Write-Host "*** Building model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    Invoke-D365ModuleCompile -Module $Model -XRefGeneration -LogPath $PackagesLocalDirectory

    Finished $TaskStartTime

    if ((Test-Path -Path "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.xppc.err.xml" -PathType Leaf) -and `
        ((Get-Item "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.xppc.err.xml").Length -gt 0))
    {
        Write-Host ""
        Write-Host "*** Compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        code "$PackagesLocalDirectory\$Model\Dynamics.AX.$Model.xppc.err.xml"
        Set-Location $currentDirectory
        [system.media.systemsounds]::Hand.play()
        Pause("Press any key to continue...")
        exit
        
    }

}
#EndRegion

# Write-Host "purging disposable data"

$DiposableTables = @(
    "formRunConfiguration"
    ,"syslastvalue"
    ,"sysPersonalization"
)

$DiposableTables | ForEach-Object {
    Write-Host "purging $_"
    $sql = "truncate table $_"
    Invoke-Sqlcmd -Query $sql -ServerInstance "." -Database "AxDb"
}

$TaskStartTime = $(Get-Date)

$Models2Compile | ForEach-Object { Invoke-CompileModel $_ }

Write-Host ""
Write-Host "*** Finished servicing all models. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""


ElapsedTime $ExecutionStartTime

Set-MpPreference -DisableRealtimeMonitoring $false
[system.media.systemsounds]::Hand.play()