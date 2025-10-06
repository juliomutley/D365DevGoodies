Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , MR2012ProcessService `
    , W3SVC `
    , SQLServerReportingServices `
| Set-Service -StartupType automatic

Start-D365Environment
Start-Service SQLServerReportingServices