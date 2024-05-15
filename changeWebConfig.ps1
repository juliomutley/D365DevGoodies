param (
    [Parameter(Mandatory=$true)]
    [string]$DBServerDBName,

    [Parameter(Mandatory=$true)]
    [string]$UserName,

    [Parameter(Mandatory=$true)]
    [string]$Password
)

$sourceFile = "K:\AosService\WebRoot\web.config"
$destFile = "K:\AosService\WebRoot\web___DEV___.config"

# Check if the source file exists
if (Test-Path -Path $sourceFile -PathType Leaf ) {
    # Check if the destination file exists
    if (Test-Path -Path $destFile -PathType Leaf ) {
        Write-Host "Destination file already exists: $destFile skiping backup"
    }
    else {
        # Duplicate the source file
        Copy-Item -Path $sourceFile -Destination $destFile -ErrorAction Stop
    }

    # Load the XML configuration file
    [xml]$xmlConfig = Get-Content $sourceFile

    $ServerNamepair = $DBServerDBName -split '\\'
    $DBServer = $ServerNamepair[0]
    $DBName = $ServerNamepair[1]

    # Update the specified keys
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.Database"]').value = $DBName
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.DbServer"]').value = $DBServer
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.ReadOnlySecondaryDbServers"]').value = $DBServer
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.SqlUser"]').value = $UserName
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.SqlPwd"]').value = $Password
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.AxAdminSqlUser"]').value = $UserName
    $xmlConfig.configuration.appSettings.SelectSingleNode('//add[@key="DataAccess.AxAdminSqlPwd"]').value = $Password
    
    # Save the updated XML back to the file
    $xmlConfig.Save($sourceFile)

    Write-Host "web.config file updated successfully."
} else {
    Write-Host "Source file not found: $sourceFile"
}
