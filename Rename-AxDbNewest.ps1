<#
.SYNOPSIS
    Promotes a restored database to AxDb on a D365 F&O dev box.

.DESCRIPTION
    Makes a restored copy (by default 'AxDbNewest') the live 'AxDb', keeping the
    previous AxDb as 'AxDb_old' for a manual rollback.

    Sequence:
      1. Checks the shell is elevated and that the source database exists. A
         misspelled name stops here, with the real database names listed, while the
         environment is still untouched.
      2. Stops the D365 services, IIS and the leftover iisexpress/Batch processes.
      3. Stops and starts SQL Server. Bouncing the engine drops every pending
         connection to AxDb, which is the usual reason a rename fails.
      4. Drops the old AxDb_old, renames AxDb to AxDb_old, renames the source to
         AxDb. Each rename is verified before the next step runs.
      5. Starts the D365 services and IIS.

    Destructive: it permanently drops the previous AxDb_old. Dev boxes only.

.PARAMETER AxDBNewest
    Database to promote to AxDb. Defaults to 'AxDbNewest'.

.EXAMPLE
    .\Rename-AxDbNewest.ps1

.EXAMPLE
    .\Rename-AxDbNewest.ps1 -AxDBNewest 'AxDb_Restored_20260728'

.NOTES
    Requires dbatools and an elevated session (it stops and starts services).
    Rollback is manual: stop the services, drop AxDb, then rename AxDb_old back
    with 'Rename-DbaDatabase -Move'.
#>
param(
    [string]$AxDBNewest = "AxDbNewest"
)

$ErrorActionPreference = 'Stop'

function Test-Db($Name) {
    [bool](Get-DbaDatabase -SqlInstance . -Database $Name)
}

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this from an elevated PowerShell session - it stops and starts Windows services."
}

Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# Check the parameter before anything is stopped or dropped, so a typo cannot leave
# the environment half torn down.
if (-not (Test-Db $AxDBNewest)) {
    Write-Warning "Database '$AxDBNewest' does not exist. Nothing was changed."
    Write-Host "Available databases:"
    (Get-DbaDatabase -SqlInstance . -ExcludeSystem).Name | Sort-Object | Write-Host
    return
}
Write-Host "Found '$AxDBNewest' - promoting it to AxDb." -ForegroundColor Cyan

Write-Host "Stopping D365 F&O services" -ForegroundColor Cyan
Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
| Stop-Service -Force
iisreset /stop

Get-Process iisexpress, Batch -ErrorAction Ignore | Stop-Process -Force

# Bouncing the engine is the reliable way to drop sessions still holding AxDb -
# a crashed AOS or an idle SSMS window will otherwise block the rename.
Write-Host "Restarting SQL Server to drop pending connections" -ForegroundColor Cyan
Stop-Service MSSQLSERVER -Force
Start-Service MSSQLSERVER

# 'Running' does not mean the engine is accepting connections yet.
$deadline = (Get-Date).AddMinutes(3)
while (-not (Test-DbaConnection -SqlInstance . -SkipPSRemoting -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).ConnectSuccess) {
    if ((Get-Date) -gt $deadline) { throw "SQL Server did not accept connections within 3 minutes." }
    Start-Sleep -Seconds 3
}
Write-Host "SQL Server is back up." -ForegroundColor Green

Write-Host "Removing an old AxDB database if it exists" -ForegroundColor Cyan
if (Test-Db 'AxDb_old') {
    Get-DbaDatabase -SqlInstance . -Database AxDb_old | Remove-DbaDatabase -Confirm:$false
    if (Test-Db 'AxDb_old') { throw "AxDb_old could not be dropped - it is still in use." }
}

Write-Host "Renaming the current AxDB database to AxDB_old" -ForegroundColor Cyan
if (Test-Db 'AxDb') {
    Rename-DbaDatabase -SqlInstance . -Database AxDb -DatabaseName AxDb_old -FileName AxDb_old -LogicalName AxDb_old -Move
    if (Test-Db 'AxDb') { throw "AxDb still exists after renaming it to AxDb_old - stopping before the next rename overwrites it." }
}
else {
    Write-Warning "No AxDb found - nothing to keep as AxDb_old."
}

Write-Host "Renaming the backup acceptance database to AxDB" -ForegroundColor Cyan
Rename-DbaDatabase -SqlInstance . -Database $AxDBNewest -DatabaseName AxDb -FileName AxDB -LogicalName AxDB -Move

$axDb = Get-DbaDatabase -SqlInstance . -Database AxDb
if (-not $axDb -or -not $axDb.IsAccessible) {
    throw "AxDb is missing or not accessible after the rename - do not start the services, check SSMS first."
}
Write-Host "AxDb is live: $([math]::Round($axDb.SizeMB)) MB, status $($axDb.Status)." -ForegroundColor Green

Write-Host "Starting D365 F&O services" -ForegroundColor Cyan
Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
| Start-Service
iisreset /start

[system.media.systemsounds]::Hand.play()
