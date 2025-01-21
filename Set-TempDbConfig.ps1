$totalCores = $Env:NUMBER_OF_PROCESSORS
$axDbSize = Get-DbaDbSpace -SqlInstance . -Database axdb | Select-Object -First 1 | Select-Object -ExpandProperty UsedSpace
$tempDbTotalSize = $axDbSize.Megabyte * 0.20
$tempdbLogSize = ($tempDbTotalSize / $totalCores) * 2

Set-DbaTempDbConfig -SqlInstance . `
    -DataFileSize $tempDbTotalSize `
    -DataFileCount $totalCores `
    -LogFileSize $tempdbLogSize `
    -DisableGrowth