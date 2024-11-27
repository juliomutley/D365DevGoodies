Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
New-DbaDbSnapshot -SqlInstance . -Database AxDB