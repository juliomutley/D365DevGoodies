choco upgrade all -y
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
#region Update visual studio
Get-Process devenv | Stop-Process -ErrorAction Ignore

dotnet tool update -g dotnet-vs
vs update --all

#endregion

.\InstallVsExtension.ps1

#region run windows update
$Module2Service = $('PSWindowsUpdate')

$Module2Service | ForEach-Object {
    if (Get-Module -ListAvailable -Name $_) {
        Write-Host "Updating powershell module" $_
        Update-Module -Name $_ -Force
    } 
    else {
        Write-Host "Installing powershell module" $_
        Install-Module -Name $_ -SkipPublisherCheck -Scope AllUsers
        Import-Module $_
    }
}
Install-Module PSWindowsUpdate
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
#endregion