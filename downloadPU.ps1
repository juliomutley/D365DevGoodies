# Run with Windows PowerShell 5.1 (powershell.exe), never PowerShell 7 (pwsh): d365fo.tools loads
# .NET Framework assemblies and fails under pwsh with misleading path errors.
#Requires -PSEdition Desktop

$SASLink = 'sashyperlink'
$DestinationFileName = 'PUXX'

Write-Host 'Installing AzCopy...'
Invoke-D365InstallAzCopy
Write-Host 'Downloading...'
Invoke-D365AzCopyTransfer -SourceUri $SASLink -DestinationUri "D:\$DestinationFileName.zip"
Write-Host 'Extracting file'
Expand-Archive -LiteralPath "D:\$DestinationFileName.zip" -DestinationPath "D:\$DestinationFileName"