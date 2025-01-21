# Define the path to the backup file
$backupFile="S:\MSSQL_BACKUP\AxDb_202410282327.bak"

# Define the drive where the data files will be stored
$dataDrive="F:"

# Define the drive where the log files will be stored
$logDrive="H:"

# Define the name of the database to be restored
$databaseName="AxDB_Newest"

# -OutputScriptOnly: Generates the T-SQL script for the restore operation without executing it
Restore-DbaDatabase -SqlInstance . -DatabaseName $databaseName -Path $backupFile -DestinationDataDirectory $dataDrive\MSSQL_DATA -DestinationLogDirectory $logDrive\MSSQL_LOGS -ReplaceDbNameInFile -OutputScriptOnly