'<#
.SYNOPSIS
    Prepares a D365 F&O development database for an environment update.

.DESCRIPTION
    Run against a local D365 F&O dev VM before refreshing the environment. The script:

      1. Installs/updates the dbatools and d365fo.tools modules.
      2. Verifies the shell is elevated and the caller is sysadmin on the local
         instance, aborting before anything destructive runs if either fails.
      3. Raises SQL Server max memory to 40% of RAM for the maintenance run,
         then drops it to 15% at the end so the AOS has room to work.
      4. Deploys Ola Hallengren's maintenance solution to master.
      5. Applies dev-friendly database settings: Simple recovery, AUTO_CLOSE OFF,
         AUTO_UPDATE_STATISTICS_ASYNC OFF, and CHANGE_TRACKING ON (2-day retention).
      6. Repoints batch configuration (SYSSERVERCONFIG / BATCHSERVERGROUP) at this
         machine and re-enables all users except axrunner and Guest.
      7. Purges disposable data: batch/DMF/log tables, completed batch jobs,
         *staging and *tmp tables, and T<n>/DMF_<n> leftover temp tables.
      8. Optionally shrinks data files and rebuilds fragmented indexes (-ShrinkData).
      9. Truncates the transaction log.

    Destructive by design — it truncates and deletes data. Never point it at production.

.PARAMETER DatabaseName
    Database to prepare. Defaults to 'axdb'.

.PARAMETER ShrinkData
    Also shrink the data files and run IndexOptimize (offline index rebuilds).
    Off by default: both are slow and I/O heavy, and shrinking re-fragments the
    indexes the rebuild then has to fix. Enable it when reclaiming disk space
    matters more than run time. The log shrink runs either way.

.EXAMPLE
    .\Prepare-D365DevelopmentDatabaseUpdate.ps1

    Purge and reconfigure AxDb, skipping the shrink/rebuild pass.

.EXAMPLE
    .\Prepare-D365DevelopmentDatabaseUpdate.ps1 -DatabaseName 'AxDB_Newest' -ShrinkData

    Full pass including data file shrink and index rebuild.

.NOTES
    Requires local admin (installs modules to AllUsers) and sysadmin on the local
    SQL Server instance; both are checked up front and the script throws rather
    than running partially. Populate $LargeTables to also age out rows older than
    two months from custom high-volume tables.
#>
param(
    [string]$DatabaseName = 'axdb',
    [switch]$ShrinkData = $false
)

$ErrorActionPreference = 'Stop'

# --- Elevation check ----------------------------------------------------------
# Module install below writes to AllUsers, so an elevated shell is required.
# Fail here rather than half way through a destructive run.
$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must run from an elevated PowerShell session (Run as Administrator)."
}

# --- Module prerequisites -----------------------------------------------------
$Module2Service = @('dbatools', 'd365fo.tools')

$Module2Service | ForEach-Object {
    $moduleName = $_
    if (Get-Module -ListAvailable -Name $moduleName) {
        Write-Host "Updating $moduleName"
        Update-Module -Name $moduleName -Force -ErrorAction Stop
    } else {
        Write-Host "Installing $moduleName"
        Install-Module -Name $moduleName -SkipPublisherCheck -AllowClobber -Scope AllUsers -ErrorAction Stop
    }
    Import-Module $moduleName -Force
}

# The dev VM uses a self-signed SQL certificate.
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# --- SQL permission check -----------------------------------------------------
# Every maintenance step below (ALTER DATABASE, truncate, drop, shrink) needs
# sysadmin on the local instance.
$isSysadmin = (Invoke-DbaQuery -SqlInstance . -Database master -Query "SELECT IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin").IsSysadmin
if ($isSysadmin -ne 1) {
    throw "$($identity.Identity.Name) is not a sysadmin on the local SQL Server instance. Aborting."
}

# --- SQL Server sizing --------------------------------------------------------
# Give SQL 40% of RAM while maintenance runs; restored to 15% at the end.
$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.4) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

$server = $env:computername

# Provides master.dbo.IndexOptimize, used by the -ShrinkData pass below.
Install-DbaMaintenanceSolution -SqlInstance $server -Database master -ReplaceExisting

# Custom high-volume tables to age out (rows older than 2 months). Optional.
$LargeTables = @(

)

# --- Database settings for a dev workload -------------------------------------
Write-Host "Setting recovery model"
Set-DbaDbRecoveryModel -SqlInstance $server -RecoveryModel Simple -Database $databaseName -Confirm:$false

Write-Host "Setting database options"
$sql = "ALTER DATABASE $databaseName SET AUTO_CLOSE OFF"
Invoke-DbaQuery -SqlInstance . -Database $databaseName -Query $sql -QueryTimeout 0

$sql = "ALTER DATABASE $databaseName SET AUTO_UPDATE_STATISTICS_ASYNC OFF"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

# Drop D365 temp tables left behind by sessions older than a day.
Clear-D365TempDbTables -DatabaseServer $server -DatabaseName $databaseName -Days 1

Enable-D365User

Write-Host "Enabling change tracking for database $databaseName"
$sql = "ALTER DATABASE $databaseName SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql

Write-Host "enabling users"
$sql = "UPDATE USERINFO SET enable = 1 WHERE id NOT IN ('axrunner', 'Guest')"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

# --- Repoint batch configuration at this machine ------------------------------
# A restored database still names the source AOS; batch jobs will not run until
# SYSSERVERCONFIG and BATCHSERVERGROUP reference this server.
Write-Host "Setting Server configurations"
$sql = "WITH ServerConfigCTE AS ( SELECT top 1 SERVERID, @@servername AS NewServerID FROM SYSSERVERCONFIG ) UPDATE ServerConfigCTE SET SERVERID = 'Batch:' + NewServerID"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0
$sql = "delete SYSSERVERCONFIG where SERVERID <> 'Batch:' + @@servername"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "Setting batchservergroup options"
$sql = "delete batchservergroup where SERVERID <> 'Batch:$server'

insert into batchservergroup(GROUPID, SERVERID, RECID, RECVERSION, CREATEDDATETIME, CREATEDBY)
select GROUP_, 'Batch:$server', 5900000000 + cast(CRYPT_GEN_RANDOM(4) as bigint), 1, GETUTCDATE(), '-admin-' from batchgroup
    where not EXISTS (select recid from batchservergroup where batchservergroup.GROUPID = batchgroup.GROUP_)"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

# --- Purge disposable data ----------------------------------------------------
# History, log and staging tables a dev environment has no use for. Truncating
# them is what actually frees the space the shrink pass can reclaim.
Write-Host "purging disposable data"

$DiposableTables = @(
     "BATCHJOBHISTORY"
    ,"BATCHCONSTRAINTSHISTORY"
    ,"BATCHHISTORY"
    ,"DMFDEFINITIONGROUPEXECUTION"
    ,"DMFDEFINITIONGROUPEXECUTIONHISTORY"
    ,"DMFEXECUTION"
    ,"DMFSTAGINGEXECUTIONERRORS"
    ,"DMFSTAGINGLOG"
    ,"DMFSTAGINGLOGDETAILS"
    ,"DMFSTAGINGVALIDATIONLOG"
    ,"EVENTCUD"
    ,"EVENTCUDLINES"
    ,"FORMRUNCONFIGURATION"
    ,"RETAILLOG"
    ,"SALESPARMLINE"
    ,"SALESPARMSUBLINE"
    ,"SALESPARMSUBTABLE"
    ,"SALESPARMTABLE"
    ,"SALESPARMUPDATE"
    ,"SYSDATABASELOG"
    ,"SYSLASTVALUE"
    ,"SYSUSERLOG"
)

$DiposableTables | ForEach-Object {
    Write-Host "purging $_"
    $sql = "truncate table $_"
    Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0
}

# Finished/cancelled/error jobs (status 3, 4, 8) and their orphaned batch tasks.
Write-Host "purging disposable batch job data"
$sql = "delete batchjob where status in (3, 4, 8)
delete batch where not exists (select recid from batchjob where batch.BATCHJOBID = BATCHJOB.recid)"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "purging staging tables data"
$sql = "EXEC sp_msforeachtable
@command1 ='truncate table ?'
,@whereand = ' And Object_id In (Select Object_id From sys.objects
Where name like ''%staging'')'"

Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "purging disposable report data"
$sql = "EXEC sp_msforeachtable
@command1 ='truncate table ?'
,@whereand = ' And Object_id In (Select Object_id From sys.objects
Where name like ''%tmp'')'"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

# T<n> tables are AOS session temp tables orphaned by crashes/restarts.
Write-Host "dropping temp tables"
$sql = "EXEC sp_msforeachtable 
@command1 ='drop table ?'
,@whereand = ' And Object_id In (Select Object_id FROM SYS.OBJECTS AS O WITH (NOLOCK), SYS.SCHEMAS AS S WITH (NOLOCK) WHERE S.NAME = ''DBO'' AND S.SCHEMA_ID = O.SCHEMA_ID AND O.TYPE = ''U'' AND O.NAME LIKE ''T[0-9]%'')' "
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "dropping DMF temp tables"
$sql = "EXEC sp_msforeachtable 
@command1 ='drop table ?'
,@whereand = ' And Object_id In (Select Object_id FROM SYS.OBJECTS AS O WITH (NOLOCK), SYS.SCHEMAS AS S WITH (NOLOCK) WHERE S.NAME = ''DBO'' AND S.SCHEMA_ID = O.SCHEMA_ID AND O.TYPE = ''U'' AND O.NAME LIKE ''DMF[_][a-z0-9]%'')' "
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "purging disposable large tables data"
$LargeTables | ForEach-Object {
    $sql = "delete $_ where $_.CREATEDDATETIME < dateadd(""MM"", -2, getdate())"
    Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0
}

# --- Optional: reclaim data file space and defragment -------------------------
# Slow and I/O heavy, so opt-in. The rebuild must follow the shrink, which leaves
# indexes heavily fragmented.
if ($ShrinkData) {
    Write-Host "Reclaiming freed database space"
    Invoke-DbaDbShrink -SqlInstance $server -Database $databaseName -FileType Data

    # Rebuild indexes over 5% fragmented and refresh all statistics.
    # http://calafell.me/defragment-indexes-on-d365-finance-operations-virtual-machine/
    Write-Host "Running Ola Hallengren's IndexOptimize tool"
    $sql = "EXECUTE master.dbo.IndexOptimize
        @Databases = '$databaseName',
        @FragmentationLow = NULL,
        @FragmentationMedium = 'INDEX_REBUILD_OFFLINE',
        @FragmentationHigh = 'INDEX_REBUILD_OFFLINE',
        @FragmentationLevel1 = 5,
        @FragmentationLevel2 = 25,
        @LogToTable = 'N',
        @UpdateStatistics = 'ALL',
        @MaxDOP = 0"

    Invoke-DbaQuery -SqlInstance $server -Database "master" -Query $sql -QueryTimeout 0
} else {
    Write-Host "Skipping data file shrink and index rebuild (use -ShrinkData to enable)"
}

# --- Wrap up ------------------------------------------------------------------
# Log truncate always runs: cheap, and Simple recovery makes the log expendable.
Write-Host "Reclaiming database log space"
Invoke-DbaDbShrink -SqlInstance $server -Database $databaseName -FileType Log -ShrinkMethod TruncateOnly

# Hand memory back so the AOS and compiler have room.
$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer