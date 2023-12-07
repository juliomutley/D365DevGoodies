
$dbName = 'AxDb'
$dataDrive='G:'
$LogDrive='H:'

If(!(test-path "$dataDrive\MSSQL_DATA"))
{
    New-Item -ItemType Directory -Force -Path "$dataDrive\MSSQL_DATA"
}

If(!(test-path "$logDrive\MSSQL_LOGS"))
{
    New-Item -ItemType Directory -Force -Path "$logDrive\MSSQL_LOGS"
}


Invoke-DbaDbShrink -SqlInstance . -Database $dbName -FileType Log -ShrinkMethod TruncateOnly

Move-DbaDbFile -SqlInstance . -Database $dbName -FileType Data -FileDestination "$dataDrive\MSSQL_DATA"
Move-DbaDbFile -SqlInstance . -Database $dbName -FileType Log  -FileDestination "$logDrive\MSSQL_LOGS"