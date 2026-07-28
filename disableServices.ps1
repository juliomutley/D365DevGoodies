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
