# Stops IIS Express, the AOSService app pool and the D365 services (disableServices.ps1 also sets their
# startup type to Disabled)
& "$PSScriptRoot\disableServices.ps1"

Get-Process Batch -ErrorAction Ignore | Stop-Process -Force -ErrorAction Ignore

Restart-Service MSSQLSERVER -Force

# Sets the D365 services back to Automatic and starts them, plus SSRS and the AOSService app pool
& "$PSScriptRoot\enableServices.ps1"

iisreset.exe
