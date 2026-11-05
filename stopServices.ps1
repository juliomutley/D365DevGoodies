# Stops IIS Express, the AOSService app pool and the D365 services (disableServices.ps1 also sets their
# startup type to Disabled), then ends what that script leaves behind.
& "$PSScriptRoot\disableServices.ps1"

Get-Process Batch, xppcAgent -ErrorAction Ignore | Stop-Process -Force

iisreset.exe /stop
