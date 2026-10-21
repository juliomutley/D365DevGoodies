<#
.SYNOPSIS
    Re-enables disabled indexes in one database on the local SQL Server.

.DESCRIPTION
    SQL Server has no ALTER INDEX ... ENABLE - REBUILD is the only enabler.
    Discovery is Find-DbaDbDisabledIndex; the rebuild is one ALTER INDEX ALL per
    affected table, which handles clustered-before-nonclustered ordering for us.

    Note: -Database on Find-DbaDbDisabledIndex is an exact match despite what its
    help says - no wildcards.

    Tradeoff: ALTER INDEX ALL rebuilds every index on the table, not just the
    disabled ones. Fine on a dev box, wasteful on a large production table.

    Connects with Windows integrated auth (dbatools' default when no
    -SqlCredential is passed).

.EXAMPLE
    .\Enable-DbaDisabledIndex.ps1 -Database AXDB -WhatIf
#>
#Requires -Modules dbatools
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [string]$Database,
    [string]$SqlInstance = 'localhost'
)

$ErrorActionPreference = 'Stop'

# -WhatIf:$false is required, not optional. Find-DbaDbDisabledIndex declares
# SupportsShouldProcess and gates its own SELECT behind ShouldProcess, so
# $WhatIfPreference propagating from this script would suppress discovery and
# make a dry run report "nothing disabled".
$disabled = Find-DbaDbDisabledIndex -SqlInstance $SqlInstance -Database $Database -EnableException -WhatIf:$false

if (-not $disabled) {
    Write-Host "No disabled indexes in $Database."
    return
}

foreach ($group in $disabled | Group-Object SchemaName, TableName) {

    $schema = $group.Group[0].SchemaName
    $table  = $group.Group[0].TableName
    $sql    = "ALTER INDEX ALL ON [$schema].[$table] REBUILD;"

    if (-not $PSCmdlet.ShouldProcess("$Database [$schema].[$table]", "REBUILD ALL ($($group.Count) disabled)")) {
        Write-Host $sql
        continue
    }

    try {
        Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $sql -EnableException
        Write-Host "Rebuilt  [$schema].[$table]  ($($group.Count) index(es) re-enabled)"
    } catch {
        Write-Warning "Failed   [$schema].[$table] : $($_.Exception.Message)"
    }
}

if (Find-DbaDbDisabledIndex -SqlInstance $SqlInstance -Database $Database -WhatIf:$false) {
    Write-Warning "Some indexes are still disabled."
}
