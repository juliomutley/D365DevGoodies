#region install modules

Set-MpPreference -DisableRealtimeMonitoring $true

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
        Import-Module $_
    }
}
#endregion

#region models
$Models2Compile = $(`
    'Model1',
    'Model2',
    'Model3'
)

$Models2UndoChanges = $(`
    'Model1',
    'Model2',
    'Model3'
)
#endregion models

#region variables
$ErrorBGColor = "Red"
$ErrorFGColor = "White"
$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$FinishedFGColor = "Green"
$currentDirectory = Get-Location
$ExecutionStartTime = $(Get-Date)
$PackagesLocalDirectory = 'k:\AOSService\PackagesLocalDirectory'

if (test-path "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"){
    $tfExe = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\TF.exe"
}
else {
    $tfExe = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\TF.exe"
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
        "-output=$PackagesLocalDirectory\$Model\Resources",
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

    Write-Host ""
    Write-Host "*** Checking Best Practices for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    $xppbpArgs = @("-metadata=$PackagesLocalDirectory\",
        "-compilermetadata=$PackagesLocalDirectory\",
        "-packagesRoot=$PackagesLocalDirectory\",
        "-all",
        "-module=$Model",
        "-model=$Model",
        "-car=$PackagesLocalDirectory\$Model\car.$Model.xlsx",
        "-xmllog=$PackagesLocalDirectory\$Model\BPCheck.$Model.xml")

    &"$PackagesLocalDirectory\Bin\xppbp.exe" $xppbpArgs
    Finished $TaskStartTime

}
#endregion Functions

stop-process -name devenv -ErrorAction Ignore

Write-Host "purging disposable data"

$DiposableTables = @(
    "formRunConfiguration"
    ,"syslastvalue"
)

$DiposableTables | ForEach-Object {
    Write-Host "purging $_"
    $sql = "truncate table $_"
    Invoke-Sqlcmd -Query $sql -ServerInstance "." -Database "AxDb"
}

Write-Host ""
Write-Host "*** Stopping services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)
Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
| Stop-Service -Force -ErrorAction SilentlyContinue

Stop-Process -Name "iisexpress" -ErrorAction SilentlyContinue

Start-Service MSSQLSERVER

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
        Write-Host "*** $Model not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Pause("Press any key to continue...")
        Set-Location $currentDirectory
        exit
    }
    Set-Location "$packagesLocalDirectory\$_"
    &$tfExe $TFArgs
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
        Write-Host "*** $Model not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Set-Location $currentDirectory
        Pause("Press any key to continue...")
        exit
    }
    Set-Location "$packagesLocalDirectory\$_"
    &$tfExe $TFArgs

    [xml]$XmlDocument = Get-Content -Path "$PackagesLocalDirectory\$_\Descriptor\*.xml"

    $ModelName = $XmlDocument.AxModelInfo.Name

    Set-Location "$packagesLocalDirectory\$_\$ModelName"
    $TFArgs = @('add', './*.xml', '/recursive')
    &$tfExe $TFArgs
}

Finished $TaskStartTime

$TaskStartTime = $(Get-Date)


$Models2Compile | ForEach-Object { Invoke-CompileModel $_ }

Write-Host ""
Write-Host "*** Finished servicing all models. ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

ElapsedTime $TaskStartTime

Write-Host ""
Write-Host "*** Starting services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
| Start-Service -ErrorAction SilentlyContinue

ElapsedTime $TaskStartTime

Write-Host ""
Write-Host "*** Syncronizing database... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

$SyncEngineArgs = @(
    '-syncmode=fullall'
    , "-metadatabinaries=$PackagesLocalDirectory\"
    , '-connect=Data Source=localhost;Initial Catalog=AxDB;Integrated Security=True'
    , '-continueOnError=False'
    , '-verbosity=Diagnostic'
    , '-enableParallelSync'
)

Remove-Item "$PackagesLocalDirectory\DBSynchronization.*"

$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.7) / 1024 / 1024

Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

&"$PackagesLocalDirectory\Bin\syncengine.exe" $SyncEngineArgs > "$PackagesLocalDirectory\DBSynchronization.log"

$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

iisreset.exe

Finished $TaskStartTime

Write-Host ""
Write-Host "*** All done! ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

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