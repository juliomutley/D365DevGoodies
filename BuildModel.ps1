Set-MpPreference -DisableRealtimeMonitoring $true
#Region Variables
$Models2Compile = $(`
     'ModelName'
)

$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$ErrorFGColor = "White"
$ErrorBGColor = "Red"
$FinishedFGColor = "Green"
$currentDirectory = Get-Location
$ExecutionStartTime = $(Get-Date)
$PackagesLocalDirectory = 'k:\AOSService\PackagesLocalDirectory'
#endregion

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

    $LableCArgs = @("-metadata=$PackagesLocalDirectory\",
        "-Output=$PackagesLocalDirectory\$Model\Resources",
        "-modelmodule=$Model"
        "-OutLog=$PackagesLocalDirectory\$Model\LabelC_outlog.log",
        "-ErrLog=$PackagesLocalDirectory\$Model\LabelC_ErrLog.log")
    &"$PackagesLocalDirectory\Bin\labelc.exe" $LableCArgs

    if ((Get-Item "$PackagesLocalDirectory\$Model\LabelC_ErrLog.log").Length -gt 0)
    {
        Write-Host ""
        Write-Host "*** Label compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Get-Content -Path "$PackagesLocalDirectory\$Model\LabelC_ErrLog.log"
        [system.media.systemsounds]::Hand.play()
        Set-Location $currentDirectory
        Pause("Press any key to continue...")
        exit
    }

    Write-Host ""
    Write-Host "*** Building model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $xppcArgs = @("-metadata=$PackagesLocalDirectory\",
        "-compilermetadata=$PackagesLocalDirectory\",
        "-xref",
        "-xrefSqlServer=localhost",
        "-xrefDbName=DYNAMICSXREFDB",
        "-output=$PackagesLocalDirectory\$Model\bin",
        "-modelmodule=$Model",
        "-xmllog=$PackagesLocalDirectory\$Model\BuildModelResult.xml",
        "-log=$PackagesLocalDirectory\$Model\BuildModelResult.log",
        "-appBase=$PackagesLocalDirectory\Bin",
        "-refPath=$PackagesLocalDirectory\$Model\bin",
        "-referenceFolder=$PackagesLocalDirectory\")

    &"$PackagesLocalDirectory\Bin\xppc.exe" $xppcArgs

    Finished $TaskStartTime

    if (test-path "$PackagesLocalDirectory\$Model\*.err.xml")
    {
        Write-Host ""
        Write-Host "*** Compilation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        code "$PackagesLocalDirectory\$Model\BuildModelResult.err.xml"
        Set-Location $currentDirectory
        [system.media.systemsounds]::Hand.play()
        Pause("Press any key to continue...")
        exit
    }

}
#EndRegion

# Write-Host "purging disposable data"

# $DiposableTables = @(
#     "formRunConfiguration"
#     ,"syslastvalue"
# )

# $DiposableTables | ForEach-Object {
#     Write-Host "purging $_"
#     $sql = "truncate table $_"
#     Invoke-Sqlcmd -Query $sql -ServerInstance "." -Database "AxDb"
# }

$TaskStartTime = $(Get-Date)

$Models2Compile | ForEach-Object { Invoke-CompileModel $_ }

Write-Host ""
Write-Host "*** Finished servicing all models. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

ElapsedTime $ExecutionStartTime

Set-MpPreference -DisableRealtimeMonitoring $false