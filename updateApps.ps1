choco upgrade all -y

#region Update visual studio
Get-Process devenv | Stop-Process

$vsVersions = @("2017", "2019", "2022")

Write-Host Downloading files
foreach ($vsVersion in $vsVersions) {
    Write-Information "Updating vs$vsversion"
    Start-Process -Wait `
    -FilePath "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe" `
    -ArgumentList "update --passive --norestart --installpath ""C:\Program Files (x86)\Microsoft Visual Studio\$vsVersion\Professional"""
}
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