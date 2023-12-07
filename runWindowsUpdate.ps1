#region run windows update
$Module2Service = $('PSWindowsUpdate')

$Module2Service | ForEach-Object {
    if (Get-Module -ListAvailable -Name $_) {
        Write-Host "Updating " + $_
        Update-Module -Name $_ -Force
    } 
    else {
        Write-Host "Installing " + $_
        Install-Module -Name $_ -SkipPublisherCheck -Scope AllUsers
        Import-Module $_
    }
}

Install-WindowsUpdate -MicrosoftUpdate -AcceptAll
#endregion