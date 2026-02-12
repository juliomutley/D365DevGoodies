param (
    [string]$reportName
)

function Remove-SSRSReport {
    param (
        [string]$reportName,
        [bool]$ServicePSModule = $false
    )

    # Ensure the ReportingServicesTools module is installed and imported
    if ($ServicePSModule) {
        $Module2Service = $("ReportingServicesTools")
        $Module2Service | ForEach-Object {
            if (Get-Module -ListAvailable -Name $_) {
                Write-Host "Updating powershell module" $_
                Update-Module -Name $_ -Force
            } 
            else {
                Write-Host "Installing powershell module" $_
                Install-Module -Name $_ -SkipPublisherCheck -Scope AllUsers
            }
            Import-Module $_
        }
    }

    # Define the SSRS server URL
    $ssrsServerUrl = "http://localhost/reportserver/"

    # Define the report path
    $reportPath = "/Dynamics/$reportName"

    # Delete the report
    Remove-RsCatalogItem -Path $reportPath -Confirm:$false
}

# Example usage:
Remove-SSRSReport -reportName $reportName