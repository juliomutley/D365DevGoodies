param (
    [string]$reportName
)

function Remove-SSRSReport {
    param (
        [string]$reportName
    )

    # Define the SSRS server URL
    $ssrsServerUrl = "http://localhost/reportserver/"

    # Define the report path
    $reportPath = "/Dynamics/$reportName"

    # Delete the report
    Remove-RsCatalogItem -Path $reportPath -Confirm:$false
}

# Example usage:
Remove-SSRSReport -reportName $reportName