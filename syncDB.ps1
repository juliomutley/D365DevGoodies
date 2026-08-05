<#
.SYNOPSIS
    Runs a full D365 F&O database synchronisation with SQL Server and Defender tuned for the job.

.DESCRIPTION
    Wraps 'Invoke-D365DbSync' with the environment tweaks that make a sync run at a
    reasonable speed on a development box, then puts everything back afterwards.

    Sequence:
      1. Tell dbatools to trust the local SQL certificate (avoids connection errors).
      2. Raise SQL Server max memory to 70% of physical RAM and set MAXDOP to 0
         (unlimited parallelism) so the sync can use the whole machine.
      3. Turn off Windows Defender real-time monitoring, which otherwise scans every
         file the sync touches and slows it down considerably.
      4. Run the database synchronisation with detailed verbosity, logging to a freshly
         emptied log directory.
      5. Restore the machine for normal development use: Defender back on, SQL Server
         max memory down to 15% of RAM, MAXDOP back to 1.
      6. Print the total elapsed time.

    Steps 3-5 run inside a try/finally, so the restore happens even if the sync throws
    or the script is cancelled — the box is never left with Defender off and SQL Server
    holding 70% of RAM.

.PARAMETER DbName
    Database the MAXDOP settings are applied to. Defaults to 'AxDb'.
    Note: this only scopes the MAXDOP calls — 'Invoke-D365DbSync' always syncs the
    database configured for the local D365 environment, not this parameter.

.PARAMETER LogPath
    Directory the sync logs are written to. Defaults to 'syncLog' under the packages
    local directory of the local D365 environment.

    The directory is deleted before the sync runs, so each run's logs stand alone —
    do not point this at anything you want to keep.

.EXAMPLE
    .\syncDB.ps1

    Syncs the local D365 environment, tuning MAXDOP on 'AxDb' and logging to
    <PackagesLocalDirectory>\syncLog.

.EXAMPLE
    .\syncDB.ps1 -DbName 'AxDb_Newest'

    Same, but applies the MAXDOP changes to 'AxDb_Newest'.

.EXAMPLE
    .\syncDB.ps1 -LogPath 'D:\temp\syncLog'

    Same, but writes the sync logs to D:\temp\syncLog.

.NOTES
    Requires: d365fo.tools, dbatools.
    Must be run elevated — it changes SQL Server instance settings and Defender
    preferences.
#>
param(
    [string]$DbName = 'AxDb',

    [string]$LogPath
)

#region functions
# Prints how long has passed since $TaskStartTime, as hh:mm:ss.
function ElapsedTime($TaskStartTime) {
    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}

# Closing banner: "Finished!" plus the total run time.
function Finished($StartTime) {
    $FinishedFGColor = "Green"
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    ElapsedTime $StartTime
}
#endregion Functions

$TaskStartTime = $(Get-Date)

# Resolved here rather than in the param block so the D365 module is loaded by the time we ask.
if (-not $LogPath) {
    $PackagesLocalDirectory = (Get-D365EnvironmentSettings).Common.BinDir
    $LogPath = Join-Path $PackagesLocalDirectory 'syncLog'
}

# dbatools refuses self-signed SQL certificates by default; local dev instances use one.
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# Memory limits are expressed in MB, so convert from the bytes WMI reports.
$totalServerMemory = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.7) / 1024 / 1024

# Give SQL Server the machine for the duration of the sync.
Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer
Set-DbaMaxDop -SqlInstance . -Database $DbName -MaxDop 0

try {
    # Real-time scanning inspects every file the sync writes; disabling it is the single
    # biggest speed-up here.
    Set-MpPreference -DisableRealtimeMonitoring $true

    # Start from an empty log directory so this run's logs are not mixed with the last one's.
    Remove-Item $LogPath -Recurse -Force -ErrorAction Ignore

    Invoke-D365DbSync -LogPath $LogPath -Verbosity Detailed
}
finally {
    # Always hand the machine back, even if the sync failed or was interrupted.
    Set-MpPreference -DisableRealtimeMonitoring $false

    $memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024
    Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer
    Set-DbaMaxDop -SqlInstance . -Database $DbName -MaxDop 1
}

Finished $TaskStartTime
