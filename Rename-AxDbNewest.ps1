$AxDBNewest="AxDb_Newest"
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
Write-Host "Stopping D365 F&O services"
Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
| Stop-Service -Force
iisreset /stop

Get-Process iisexpress, Batch -ErrorAction Ignore | Stop-Process -Force

Write-Host "Removing an old AxDB database if it exists"
Get-DbaDatabase -SqlInstance . -Database AxDb_old | Remove-DbaDatabase -Confirm:$false

Write-Host "Renaming the current AxDB database to AxDB_old"
Rename-DbaDatabase -SqlInstance . -Database AxDb -DatabaseName AxDb_old -FileName AxDb_old -LogicalName AxDb_old -Move

Write-Host "Renaming the backup acceptance database to AxDB"
Rename-DbaDatabase -SqlInstance . -Database $AxDBNewest -DatabaseName AxDb -FileName AxDB -LogicalName AxDB -Move

Write-Host "Starting D365 F&O services"
Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
| Start-Service
iisreset /start

[system.media.systemsounds]::Hand.play()