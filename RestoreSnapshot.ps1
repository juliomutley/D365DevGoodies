Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
Restore-DbaDbSnapshot -SqlInstance . -Database AxDB -Force