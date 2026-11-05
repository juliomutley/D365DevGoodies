<#
.SYNOPSIS
Functions that stop and start the web hosts of a D365 F&O development box: IIS Express and the
AOSService app pool (the w3wp worker process).

.DESCRIPTION
Meant to be dot-sourced, so the callers share one copy of these steps:

    . "$PSScriptRoot\D365WebHost.ps1"

Both hosts keep the built assemblies and metadata of the models loaded, which locks the files a build
clears and leaves them serving the old build. Callers stop them first and, for the app pool, start it
again afterwards.

  Stop-D365IISExpress   Stops IIS Express (the Dynamics365 app pool Visual Studio starts). There is no
                        matching start: Visual Studio launches IIS Express itself the next time the
                        web application is run or debugged.
  Stop-D365AosAppPool   Stops the AOSService app pool in IIS (ends its w3wp process).
  Start-D365AosAppPool  Starts the AOSService app pool again.
  Stop-D365WebHost      Both stops: IIS Express, then the AOS app pool.
  Start-D365WebHost     Starts the AOS app pool (what Stop-D365WebHost stopped that can be started).

Every function does nothing when its host is not running, so callers need no checks of their own, and
stopping twice is harmless.

.NOTES
- Run it with Windows PowerShell 5.1 (`powershell.exe`), never PowerShell 7 (`pwsh`): d365fo.tools loads
  .NET Framework assemblies, and under `pwsh` the D365 tooling fails with misleading path errors. A
  `#Requires -PSEdition Desktop` line makes `pwsh` refuse to start the script with a clear message.
  From a `pwsh` or VS Code terminal:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\D365WebHost.ps1'"`
Needs administrator rights for the app pool calls (`appcmd.exe`). Defines functions only; dot-sourcing it
changes nothing.
#>

#Requires -PSEdition Desktop

$script:AppCmdPath = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
$script:AosAppPoolName = 'AOSService'

function Stop-D365IISExpress {
    $IISExpressProcesses = @(Get-Process -Name iisexpress -ErrorAction Ignore)

    if ($IISExpressProcesses.Count -gt 0) {
        Write-Host "Stopping IIS Express (process $($IISExpressProcesses.Id -join ', '))..."
        $IISExpressProcesses | Stop-Process -Force -ErrorAction Ignore
        $IISExpressProcesses | Wait-Process -Timeout 30 -ErrorAction Ignore
    }
}

function Stop-D365AosAppPool {
    # appcmd needs the Windows Process Activation Service; with it stopped there is no w3wp to end
    $IsAppPoolHostRunning = (Get-Service -Name WAS -ErrorAction Ignore).Status -eq 'Running'

    if ($IsAppPoolHostRunning) {
        Write-Host "Stopping app pool $script:AosAppPoolName..."
        & $script:AppCmdPath stop apppool "/apppool.name:$script:AosAppPoolName" | Out-Null
    }
}

function Start-D365AosAppPool {
    $IsAppPoolHostRunning = (Get-Service -Name WAS -ErrorAction Ignore).Status -eq 'Running'

    if ($IsAppPoolHostRunning) {
        Write-Host "Starting app pool $script:AosAppPoolName..."
        & $script:AppCmdPath start apppool "/apppool.name:$script:AosAppPoolName" | Out-Null
    }
}

function Stop-D365WebHost {
    Stop-D365IISExpress
    Stop-D365AosAppPool
}

function Start-D365WebHost {
    Start-D365AosAppPool
}
