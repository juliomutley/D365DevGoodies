# Ensure the folder exists
$DestinationFolder = "D:\BacPac"
if (!(Test-Path -Path $DestinationFolder)) {
       New-Item -ItemType Directory -Path $DestinationFolder
}

$DestinationParms = Get-D365AzureStorageUrl -OutputAsHashtable
$BlobFileDetails = Get-D365LcsDatabaseBackups -Latest | Invoke-D365AzCopyTransfer @DestinationParms
$BlobFileDetails | Invoke-D365AzCopyTransfer -DestinationUri $DestinationFolder