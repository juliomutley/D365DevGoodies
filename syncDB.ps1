#region functions
function ElapsedTime($TaskStartTime) {
    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}
function Finished($StartTime) {
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    ElapsedTime $StartTime
}
#endregion Functions

$TaskStartTime = $(Get-Date)
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.7) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer
Set-DbaMaxDop -SqlInstance . -Database AxDb -MaxDop 0

Set-MpPreference -DisableRealtimeMonitoring $true

Invoke-D365DbSync -MaxDop 0 -Verbosity Detailed

Set-MpPreference -DisableRealtimeMonitoring $false
$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024
Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer
Set-DbaMaxDop -SqlInstance . -Database AxDb -MaxDop 1

Finished $TaskStartTime