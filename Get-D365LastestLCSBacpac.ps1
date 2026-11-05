# Run with Windows PowerShell 5.1 (powershell.exe), never PowerShell 7 (pwsh): d365fo.tools loads
# .NET Framework assemblies and fails under pwsh with misleading path errors.
#Requires -PSEdition Desktop

# Ensure the folder exists
$DestinationFolder = "D:\BacPac"
if (!(Test-Path -Path $DestinationFolder)) {
       New-Item -ItemType Directory -Path $DestinationFolder
}

$DestinationParms = Get-D365AzureStorageUrl -OutputAsHashtable
$BlobFileDetails = Get-D365LcsDatabaseBackups -Latest | Invoke-D365AzCopyTransfer @DestinationParms
$BlobFileDetails | Invoke-D365AzCopyTransfer -DestinationUri $DestinationFolder