$bacpacFile = "C:\Temp\Accbackup.bacpac" 
$startTime = $(get-date)
$sqlargs = @(
    "/Action:Import"
    , "/SourceFile:$bacpacFile"
    , "/DiagnosticsFile:$bacpacFile.importlog"
    , '/TargetConnectionString:"Data Source=localhost;Initial Catalog=AxDB;Integrated Security=True;"'
    , '/p:CommandTimeout="0"'
)

Invoke-D365InstallSqlPackage

&"C:\temp\d365fo.tools\SqlPackage.exe" $sqlargs

$elapsedTime = new-timespan $startTime $(get-date)
write-host "Elapsed:$($elapsedTime.ToString("hh\:mm\:ss"))"

Write-Host "Press any key to continue..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")