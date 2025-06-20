<#
.SYNOPSIS
    Uninstalls a specified MSI-based application from the system.

.DESCRIPTION
    This script locates an installed application using WMI based on a partial or full name match,
    prompts the user for confirmation, and then proceeds with uninstallation if approved.

.PARAMETER SoftwareName
    The name (or partial name) of the software to search for and uninstall.

.EXAMPLE
    .\UninstallApp.ps1 -SoftwareName "Example Software"

    This command searches for an installed application whose name matches "Example Software"
    and, after confirmation, uninstalls it.

.NOTES
    Use caution with Win32_Product as it can trigger reconfigurations of installed MSI apps.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SoftwareName
)

# Search for matching application
$app = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -match $SoftwareName
}

if ($app) {
    Write-Host "Found application: $($app.Name)" -ForegroundColor Green
    $confirm = Read-Host "Are you sure you want to uninstall this application? (Y/N)"
    
    if ($confirm -eq 'Y') {
        Write-Host "Uninstalling $($app.Name)..."
        $app.Uninstall()
        Write-Host "Uninstallation complete." -ForegroundColor Cyan
    } else {
        Write-Host "Uninstallation cancelled by user." -ForegroundColor Yellow
    }
} else {
    Write-Host "No application found matching '$SoftwareName'." -ForegroundColor Red
}
