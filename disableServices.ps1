Stop-D365Environment -Kill

Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , MR2012ProcessService `
    , W3SVC `
    , SQLServerReportingServices `
| Set-Service -StartupType Disabled
