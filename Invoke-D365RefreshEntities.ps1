<#
.SYNOPSIS
Triggers the Dynamics 365 Finance & Operations data entity list refresh by opening the
VFFDevEntityListRefresh menu item.

.DESCRIPTION
Opens `<D365 URL>/?mi=VFFDevEntityListRefresh` in the default browser. The menu item (VFFDevTools
model) runs the same asynchronous refresh as the "Refresh entity list" button on the Data
management framework parameters form. The refresh itself runs server-side; this script only
starts it, so it returns as soon as the browser is launched.

Requires an interactive, signed-in browser session to the environment, and the VFFDevTools model
to be deployed and built.

.PARAMETER MenuItem
Name of the action menu item to open. Defaults to VFFDevEntityListRefresh.

.PARAMETER Url
Base URL of the D365 environment. Defaults to the local environment's URL from `Get-D365Url`
(d365fo.tools).

.EXAMPLE
.\Invoke-D365RefreshEntities.ps1

.EXAMPLE
.\Invoke-D365RefreshEntities.ps1 -Url 'https://myenv.cloud.onebox.dynamics.com'
#>
[CmdletBinding()]
param (
    [string] $MenuItem = 'VFFDevEntityListRefresh',

    [string] $Url
)

if ([string]::IsNullOrWhiteSpace($Url)) {
    Import-Module d365fo.tools -ErrorAction Stop
    $Url = (Get-D365Url).Url
}

$menuItemUrl = '{0}/?mi={1}' -f $Url.TrimEnd('/'), $MenuItem

Write-Host "Opening $menuItemUrl"
Start-Process $menuItemUrl
