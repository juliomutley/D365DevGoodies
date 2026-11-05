<#
.SYNOPSIS
This script imports a BACPAC file into a SQL Server database.

.DESCRIPTION
The script imports a BACPAC file into a SQL Server database using the SqlPackage.exe utility. It also sets the maximum degree of parallelism (MaxDop) and maximum memory for the SQL Server instance.

.PARAMETER bacpacFile
The path of the BACPAC file to import.

.EXAMPLE
.\importBacPac.ps1 -bacpacFile "L:\DB Backup\AxDb_Newest.bacpac"
Imports the BACPAC file located at "L:\DB Backup\AxDb_Newest.bacpac" into the SQL Server database.

.NOTES
- Run it with Windows PowerShell 5.1 (`powershell.exe`), never PowerShell 7 (`pwsh`): d365fo.tools loads
  .NET Framework assemblies, and under `pwsh` the D365 tooling fails with misleading path errors. A
  `#Requires -PSEdition Desktop` line makes `pwsh` refuse to start the script with a clear message.
  From a `pwsh` or VS Code terminal:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\importBacPac.ps1'"`
- This script requires the SqlPackage.exe utility to be installed on the system.
- The script uses the dbatools module for setting MaxDop and MaxMemory values.

.LINK
SqlPackage.exe: https://docs.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage?view=sql-server-ver15
dbatools module: https://dbatools.io/

#>

#Requires -PSEdition Desktop

$bacpacFile = "D:\BacPac\PreProd.bacpac" 
$startTime = $(get-date)
$arguments = @(
    "/Action:Import"
    , "/SourceFile:$bacpacFile"
    , "/DiagnosticsFile:$bacpacFile.importlog"
    , '/TargetConnectionString:"Data Source=localhost;Initial Catalog=AxDB_Newest;Integrated Security=True;Trust Server Certificate=True;"'
    , '/p:CommandTimeout="0"'
)

if (!(Test-Path -Path $bacpacFile)) {
    Write-Host "BACPAC file not found at $bacpacFile"
    exit 1
}

& ./disableservices.ps1
Invoke-D365InstallSqlPackage -Latest

Set-DbaMaxDop -SqlInstance localhost -MaxDop 0
#Alocating 40% of the total server memory for sql server
$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.40) / 1024 / 1024
Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

&"C:\temp\d365fo.tools\SqlPackage\SqlPackage.exe" $arguments

#Setting MaxDop to 1 and allocating 15% of the total server memory for sql server
$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024
Set-DbaMaxDop -SqlInstance . -MaxDop 1
Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

$elapsedTime = new-timespan $startTime $(get-date)
write-host "Elapsed:$($elapsedTime.ToString("hh\:mm\:ss"))"

Write-Host "Press any key to continue..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")