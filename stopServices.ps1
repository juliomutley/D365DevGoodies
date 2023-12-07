Get-Service DynamicsAxBatch `
    , Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe `
    , W3SVC `
    , MR2012ProcessService `
| Stop-Service -Force

Get-Process iisexpress, Batch, xppcAgent -ErrorAction Ignore | Stop-Process -Force

iisreset.exe /stop