<#
.SYNOPSIS
    Tab-completion source for database-name parameters.

.DESCRIPTION
    Returns the user databases on a SQL Server instance as CompletionResult objects.
    Not meant to be run by hand: other scripts attach it to a parameter so that
    pressing Tab lists the real databases.

    Wire it up in the consuming script's param block:

        param(
            [ArgumentCompleter({ param($c, $p, $w, $a, $f) & "$PSScriptRoot\Get-DbNameCompletion.ps1" -WordToComplete $w -BoundParameters $f })]
            [string]$DatabaseName = 'AxDb'
        )

    This is the single place that knows how to list databases - change it here, never in
    a caller. Completion only suggests; it does not restrict what can be typed.

    Never throws: with no dbatools or no reachable SQL Server it returns nothing, so
    Tab simply falls back to file-name completion instead of printing an error mid-line.

.PARAMETER WordToComplete
    What has been typed so far. Matched as a prefix, case-insensitively.

.PARAMETER BoundParameters
    The caller's $fakeBoundParameters. When the user has already typed -SqlInstance
    that instance is queried; otherwise the local default instance ('.').

.PARAMETER SqlInstance
    Instance to query when BoundParameters carries no SqlInstance. Defaults to '.'.

.PARAMETER IncludeSystem
    Also offer master, model, msdb and tempdb.
#>
param(
    [string]$WordToComplete = '',
    [System.Collections.IDictionary]$BoundParameters,
    [string]$SqlInstance = '.',
    [switch]$IncludeSystem
)

try {
    if ($BoundParameters -and $BoundParameters['SqlInstance']) {
        $SqlInstance = [string]$BoundParameters['SqlInstance']
    }

    # Tab was pressed after an opening quote: match on the bare text.
    $prefix = $WordToComplete.Trim('"', "'")

    # Completion must stay silent, so every dbatools stream is muted.
    $ErrorActionPreference = 'Stop'
    $WarningPreference = 'SilentlyContinue'
    $ProgressPreference = 'SilentlyContinue'

    if (-not (Get-Command Get-DbaDatabase -ErrorAction SilentlyContinue)) {
        Import-Module dbatools -ErrorAction Stop
    }

    # A fresh dev box has no trusted cert for the engine; without this the first Tab fails.
    Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true

    $databases = if ($IncludeSystem) {
        Get-DbaDatabase -SqlInstance $SqlInstance -EnableException
    }
    else {
        Get-DbaDatabase -SqlInstance $SqlInstance -ExcludeSystem -EnableException
    }

    $databases.Name |
        Where-Object { $_ -like ([WildcardPattern]::Escape($prefix) + '*') } |
        Sort-Object |
        ForEach-Object {
            # Quote names with spaces or special characters so they paste back as one argument.
            $text = if ($_ -match '^[\w.]+$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
            [System.Management.Automation.CompletionResult]::new($text, $_, 'ParameterValue', $_)
        }
}
catch {
    # Deliberately empty - see .DESCRIPTION.
}
