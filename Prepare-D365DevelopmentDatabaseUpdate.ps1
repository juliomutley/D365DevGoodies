$Module2Service = $('dbatools',
    'd365fo.tools')

$Module2Service | ForEach-Object {
    if (Get-Module -ListAvailable -Name $_) {
        Write-Host "Updating " + $_
        Update-Module -Name $_ -Force
    } 
    else {
        Write-Host "Installing " + $_
        Install-Module -Name $_ -SkipPublisherCheck -Scope AllUsers
        Import-Module $_
    }
}

Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.4) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

$databaseName = 'AxDb_Newest'
$server = $env:computername
Install-DbaMaintenanceSolution -SqlInstance $server -Database master

$LargeTables = @(

)

Write-Host "Setting recovery model"
Set-DbaDbRecoveryModel -SqlInstance $server -RecoveryModel Simple -Database $databaseName -Confirm:$false

Write-Host "Setting database options"
$sql = "ALTER DATABASE $databaseName SET AUTO_CLOSE OFF"
Invoke-DbaQuery -SqlInstance . -Database $databaseName -Query $sql -QueryTimeout 0

$sql = "ALTER DATABASE $databaseName SET AUTO_UPDATE_STATISTICS_ASYNC OFF"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

Write-Host "enabling users"
$sql = "UPDATE USERINFO SET enable = 1 WHERE id NOT IN ('axrunner', 'Guest')"
Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $sql -QueryTimeout 0

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
    ,"INVENTSUMLOGTTS"
    ,"MP.PEGGINGIDMAPPING"
    ,"REQPO"
    ,"REQTRANS"
    ,"REQTRANSCOV"
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

Write-Host "Reclaiming freed database space"
Invoke-DbaDbShrink -SqlInstance $server -Database $databaseName -FileType Data

Write-Host "Running Ola Hallengren's IndexOptimize tool"
# http://calafell.me/defragment-indexes-on-d365-finance-operations-virtual-machine/
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

Write-Host "Reclaiming database log space"
Invoke-DbaDbShrink -SqlInstance $server -Database $databaseName -FileType Log -ShrinkMethod TruncateOnly

$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer