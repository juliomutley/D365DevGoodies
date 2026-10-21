<#
.SYNOPSIS
    Truncates the disposable user-data tables in a D365 F&O database.

.DESCRIPTION
    Single source of truth for the "disposable user data" table list. UpdateDevAll.ps1,
    dailyRunAll.ps1 and Invoke-D365ModelCompile.ps1 all call this script for their -ResetUserData
    switch, so a table is added once here and every caller picks it up.

    The four tables hold per-user state that is derived from metadata rather than being business
    data, and that can be left stale or outright invalid by a metadata change:

      formRunConfiguration  saved form setups, keyed on controls that may no longer exist
      SysLastValue          last-value / "remember my choice" data for dialogs and reports
      SysUserLog           the user session log, which grows without bound on a dev box
      sysPersonalization    per-user form personalisations, the usual cause of a form that
                            renders broken only for one user after a build

    D365 recreates all four on demand, so losing them costs a developer their saved filters and
    personalisations and nothing more.

    WARNING: this uses 'truncate table', which is not logged per row and cannot be rolled back or
    recovered from. Point it at a development database only.

.PARAMETER SqlInstance
    SQL Server instance to connect to. Defaults to '.', the local default instance.

.PARAMETER DatabaseName
    Database to purge. Defaults to 'AxDb', the local D365 development database.

.EXAMPLE
    .\Reset-D365UserData.ps1

    Purges the four tables in AxDb on the local instance.

.EXAMPLE
    .\Reset-D365UserData.ps1 -DatabaseName 'AxDb_Newest'

    Same, against a restored copy that has not yet been promoted to AxDb.

.NOTES
    Requires: dbatools. The orchestrator scripts install it -Scope AllUsers, so it is normally
    already present.

    Needs a login with rights to truncate in the target database (ALTER on each table); sysadmin
    on a local dev instance covers this.

    Does not stop or start D365 services. Truncating while the AOS is running is safe for these
    tables, but a user with a session open may see their personalisations vanish mid-use.
#>
param(
    [string] $SqlInstance = '.',
    [string] $DatabaseName = 'AxDb'
)

$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"

# Derived per-user state only -- never business data. Interpolated straight into the query below,
# so this must stay a hardcoded literal and never be driven by a parameter.
$DisposableTables = @(
     "formRunConfiguration"
    ,"SysLastValue"
    ,"SysUserLog"
    ,"sysPersonalization"
)

Write-Host ""
Write-Host "*** Purging disposable user data in $DatabaseName... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
Write-Host ""

# dbatools refuses self-signed SQL certificates by default; local dev instances use one.
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

$DisposableTables | ForEach-Object {
    Write-Host "purging $_"
    $sql = "truncate table $_"
    # SysUserLog can be very large on a long-lived dev box, so allow the truncate to take its time.
    Invoke-DbaQuery -SqlInstance $SqlInstance -Database $DatabaseName -Query $sql -QueryTimeout 0

}

Invoke-D365DataFlush -Class SysFlushData,SysFlushAod,SysDataCacheParameters
