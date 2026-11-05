# Run with Windows PowerShell 5.1 (powershell.exe), never PowerShell 7 (pwsh), to stay consistent with the
# other D365DevGoodies scripts: powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\get-VMShutdownStatus.ps1'"
#Requires -PSEdition Desktop

install-module AzureAd
Install-Module Az.Compute
Install-Module Az.Resources
Install-Module Az.Accounts
Import-Module AzureAd
Import-Module Az.Compute
Import-Module Az.Resources
import-module Az.Accounts

Connect-AzAccount

[array]$VMArray = Get-AzVm | Select-Object -Property ResourceGroupName, Name, VmId, Id
$ShutdownInformation = (Get-AzResource -ResourceType Microsoft.DevTestLab/schedules -ExpandProperties).Properties

foreach($vm in $VMArray) {
    $ShutdownStatus = "Not Configured"
    $Schedule = $ShutdownInformation | Where-Object { $_.targetResourceId -eq $vm.Id } | Select -First 1
    if($Schedule -eq $null -and $Schedule.status -ne "Enabled") {
        Write-Host $vm.name $ShutdownStatus
    }
}