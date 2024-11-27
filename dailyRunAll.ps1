[CmdletBinding()]
Param(   
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [String] $tenantId,

    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [String] $clientId,

    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [string] $secretKey
)

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
$Models2Compile = $(`
      'model1'
    , 'model2'
)

$Models2UndoChanges = $(`
      'ISVModel1'
    , 'ISVModel2'
)
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
    Write-Host ""
    Write-Host "*** $message ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
    Write-Host
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

    Write-Host ""
    Write-Host "*** Checking Best Practices for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
    Write-Host ""

    $TaskStartTime = $(Get-Date)

    Invoke-D365BestPractice -Module $Model -Model $Model -LogPath $PackagesLocalDirectory
    Finished $TaskStartTime

}
#endregion Functions

#Region Main
stop-process -name devenv -ErrorAction Ignore

Write-Host ""
Write-Host "*** Stopping services... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

Write-Host "purging disposable data"

$DiposableTables = @(
    "formRunConfiguration"
    ,"SysLastValue"
    ,"SysUserLog"
)

$DiposableTables | ForEach-Object {
    Write-Host "purging $_"
    $sql = "truncate table $_"
    Invoke-DbaQuery -Query $sql -SqlInstance "." -Database "AxDb"
}

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
        Write-Host "*** $Model not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
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
        Write-Host "*** $Model failed to undo changes, aborting... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
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
        Write-Host "*** $Model not found, try a get latest from Visual Studio... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
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
        Write-Host "*** $Model failed to get latest changes, aborting... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
        Write-Host ""
        Pause("Press any key to continue...")
        Set-Location $currentDirectory
        exit
    }

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


ElapsedTime $TaskStartTime
#end region

#region sync db
Write-Host ""
Write-Host "*** Syncronizing database... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

$TaskStartTime = $(Get-Date)

Remove-Item "$PackagesLocalDirectory\syncLog" -Recurse -force -ErrorAction Ignore

$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.7) / 1024 / 1024

Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

Invoke-D365DbSync -LogPath "$PackagesLocalDirectory\syncLog"

$memoryForSqlServer = ($totalServerMemory * 0.35) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

K:\git\d365-resources\365_PowerShell\enableServices.ps1
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
Set-Location K:\git\d365-resources\365_PowerShell
.\updateApps.ps1
#endregion SO maintenance

Set-MpPreference -DisableRealtimeMonitoring $false

Stop-Transcript
exit