# Load the dbatools module
Import-Module dbatools

# Set the database connection parameters
$impersonateEmail = "impersonate@example.com"  # Replace with the desired impersonation email

$serverName = "******"
$databaseName = "*******"
$username = "******"
$password = "*******"

# create the credential object
$PWord = ConvertTo-SecureString -String $password -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $PWord

# Define the SQL script to handle large concatenated strings using FOR XML PATH
$sqlScript = @"
    WITH ConcatenatedQuery AS (
        SELECT (
            SELECT
                'select ''' + c.TABLE_SCHEMA + '.' + c.TABLE_NAME + '.' + c.COLUMN_NAME + ''' from ' +
                c.TABLE_SCHEMA + '.' + c.TABLE_NAME + ' where ' + c.COLUMN_NAME + ' <> '''' and ' + c.COLUMN_NAME + ' <> ''$impersonateEmail'' union '
            FROM information_schema.COLUMNS c
            WHERE (c.COLUMN_NAME LIKE '%email%')
              AND (table_name NOT LIKE '%staging%'
                   AND table_name NOT LIKE '%TMP%')
              AND c.DATA_TYPE = 'nvarchar'
              AND EXISTS (
                SELECT 1
                FROM information_schema.TABLES t
                WHERE c.TABLE_NAME = t.TABLE_NAME
                  AND t.TABLE_TYPE = 'BASE TABLE'
              )
            ORDER BY c.TABLE_NAME
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(max)') AS QueryString
    )
    SELECT
        LEFT(QueryString, LEN(QueryString) - LEN(' union ')) AS FinalString
    FROM ConcatenatedQuery;
"@

# Execute the query using Invoke-DbaQuery
try {
    $results = Invoke-DbaQuery -SqlInstance $serverName -Database $databaseName -SqlCredential $Credential -Query $sqlScript -QueryTimeout 0
}
catch {
    Write-Error "Failed to execute the query: $_"
    exit 1
}

# Process the result
if ($results) {
    $finalString = $results.FinalString

    # Execute the query using Invoke-DbaQuery
    try {
        $results = Invoke-DbaQuery -SqlInstance $serverName -Database $databaseName -SqlCredential $Credential -Query $finalString -QueryTimeout 0
    }
    catch {
        Write-Error "Failed to execute the query: $_"
        exit 1
    }

    # Iterate over each query and extract schema, tableName, and field
    if ($results) {
        foreach ($row in $results) {

            # Split the string by "."
            $parts = $row[0] -split '\.'

            # Access individual parts
            $schema = $parts[0]      # "schema"
            $tableName = $parts[1]   # "tableName"
            $field = $parts[2]       # "field"

            # Build the update script
            $updateScript = "UPDATE [$schema].[$tableName] SET [$field] = '$impersonateEmail' WHERE [$field] <> '' AND [$field] <> '$impersonateEmail' ;"

            ## Output the update script
            Write-Output $updateScript
            Invoke-DbaQuery -SqlInstance $serverName -Database $databaseName -SqlCredential $Credential -Query $updateScript -QueryTimeout 0
        }
    }
    else {
        Write-Output "No results were returned from the query."
    }
}