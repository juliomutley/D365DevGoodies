function Get-BacpacModelHash {
    param (
        [Parameter(Mandatory=$true)]
        [string]$modelXmlPath
    )

    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create("System.Security.Cryptography.SHA256CryptoServiceProvider")

    $fileStream = New-Object System.IO.FileStream -ArgumentList @($modelXmlPath, [System.IO.FileMode]::Open)

    $hash = $hasher.ComputeHash($fileStream)

    $hashString = ""

    foreach ($b in $hash) { $hashString += $b.ToString("X2") }

    $fileStream.Close()

    write-host "Hash: $hashString"

    return $hashString
}