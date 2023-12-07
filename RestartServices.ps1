Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
    , MSSQLSERVER `
| Stop-Service -ErrorAction Ignore

Get-Process iisexpress, Batch -ErrorAction Ignore | Stop-Process -Force -ErrorAction Ignore

Start-Service MSSQLSERVER

Get-Service W3SVC `
    , MR2012ProcessService `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , DynamicsAxBatch `
| Start-Service 

iisreset.exe 