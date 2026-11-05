# Run with Windows PowerShell 5.1 (powershell.exe), never PowerShell 7 (pwsh): d365fo.tools loads
# .NET Framework assemblies and fails under pwsh with misleading path errors.
#Requires -PSEdition Desktop

Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , MR2012ProcessService `
    , W3SVC `
    , SQLServerReportingServices `
| Set-Service -StartupType automatic

Start-D365Environment
Start-Service SQLServerReportingServices

# Starts the AOSService app pool (IIS Express is left for Visual Studio to start)
. "$PSScriptRoot\D365WebHost.ps1"
Start-D365WebHost