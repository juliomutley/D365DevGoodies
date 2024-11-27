[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [string] $directoryPath = "K:\git\d365-resources\365_PowerShell\DatabaseLite"
)

Begin {
    # Import the Az.Accounts module if not already loaded
    if (-not (Get-Module -Name Az.Accounts -ListAvailable)) { Import-Module Az.Accounts }

    # Connect to Azure account
    try { Connect-AzAccount -ErrorAction Stop } catch { Write-Error "Failed to connect to Azure: $_"; exit }
}

Process {
    # Process each CSV file in the directory
    Get-ChildItem -Path $directoryPath -Filter *.csv | ForEach-Object { 
        $filePath = $_.FullName
        $AzureKeyVaultName = $_.BaseName
        
        # Read the CSV file content
        $csvContent = Import-Csv $filePath -Delimiter ';'
        
        # Import secrets from CSV and set them in Azure Key Vault
        try {
            $csvContent | ForEach-Object {
                Write-Host "Importing secret $($_.Name) from $filePath to $AzureKeyVaultName"
                Set-AzKeyVaultSecret -VaultName $AzureKeyVaultName -Name $_.Name -SecretValue (ConvertTo-SecureString $_.Secret -AsPlainText -Force)
            }
        }
        catch {
            Write-Error "Failed to import secrets from $filePath\: $_"
        }
    }
}

End {
    Write-Host "Processing completed."
}
