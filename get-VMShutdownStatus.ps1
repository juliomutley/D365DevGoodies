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