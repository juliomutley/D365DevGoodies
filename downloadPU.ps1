$SASLink = 'sashyperlink'
$DestinationFileName = 'PUXX'

Write-Host 'Installing AzCopy...'
Invoke-D365InstallAzCopy
Write-Host 'Downloading...'
Invoke-D365AzCopyTransfer -SourceUri $SASLink -DestinationUri "D:\$DestinationFileName.zip"
Write-Host 'Extracting file'
Expand-Archive -LiteralPath "D:\$DestinationFileName.zip" -DestinationPath "D:\$DestinationFileName"