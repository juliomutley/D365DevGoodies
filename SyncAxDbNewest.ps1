$dbName = 'AxDbNewest'
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
$totalServerMemory = Get-WMIObject -Computername . -class win32_ComputerSystem | Select-Object -Expand TotalPhysicalMemory
$memoryForSqlServer = ($totalServerMemory * 0.7) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer

Set-MpPreference -DisableRealtimeMonitoring $true

Invoke-D365DbSync -DatabaseName $dbName

Set-MpPreference -DisableRealtimeMonitoring $false

$memoryForSqlServer = ($totalServerMemory * 0.15) / 1024 / 1024

Set-DbaMaxMemory -SqlInstance . -Max $memoryForSqlServer