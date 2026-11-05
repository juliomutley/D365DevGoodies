# Run with Windows PowerShell 5.1 (powershell.exe), never PowerShell 7 (pwsh): d365fo.tools loads
# .NET Framework assemblies and fails under pwsh with misleading path errors.
#Requires -PSEdition Desktop

. "$PSScriptRoot\D365WebHost.ps1"

# Stops IIS Express and the AOSService app pool. IIS Express is not restarted by enableServices.ps1:
# Visual Studio starts it again when needed
Stop-D365WebHost

Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , MR2012ProcessService `
    , W3SVC `
| Set-Service -StartupType Disabled


Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , MR2012ProcessService `
    , W3SVC `
| Stop-Service
