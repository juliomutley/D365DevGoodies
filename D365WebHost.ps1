<#
.SYNOPSIS
Functions that stop and start the web hosts of a D365 F&O development box: IIS Express and the
AOSService app pool (the w3wp worker process).

.DESCRIPTION
Meant to be dot-sourced, so the callers share one copy of these steps:

    . "$PSScriptRoot\D365WebHost.ps1"

Both hosts keep the built assemblies and metadata of the models loaded, which locks the files a build
clears and leaves them serving the old build. Callers stop them first and start them again afterwards.

  Stop-D365IISExpress   Stops IIS Express (the Dynamics365 app pool Visual Studio starts) and remembers
                        the command line it ran with in a state file.
  Start-D365IISExpress  Starts IIS Express again from that state file, then removes the file.
  Stop-D365AosAppPool   Stops the AOSService app pool in IIS (ends its w3wp process).
  Start-D365AosAppPool  Starts the AOSService app pool again.
  Stop-D365WebHost      Both stops: IIS Express, then the AOS app pool.
  Start-D365WebHost     Both starts: the AOS app pool, then IIS Express.

Every function does nothing when its host is not running, so callers need no checks of their own.
The state file lives in `C:\temp`, so a stop in one script (disableServices.ps1) can be undone by a start in
another (enableServices.ps1).

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

$script:IISExpressStateFile = 'C:\temp\D365WebHost.iisexpress.json'
$script:AppCmdPath = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
$script:AosAppPoolName = 'AOSService'

function Stop-D365IISExpress {
    $IISExpressProcess = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'iisexpress.exe'" |
        Select-Object -First 1

    $IsCommandLineKnown = $IISExpressProcess -and
        $IISExpressProcess.CommandLine -match '^"?(?<exe>[^"]+?iisexpress\.exe)"?\s*(?<args>.*)$'

    if ($IsCommandLineKnown) {
        # Remember how it was started, so Start-D365IISExpress can bring it back the same way
        New-Item -ItemType Directory -Path (Split-Path $script:IISExpressStateFile) -Force | Out-Null
        [pscustomobject]@{ Executable = $Matches['exe']; Arguments = $Matches['args'] } |
            ConvertTo-Json | Set-Content -Path $script:IISExpressStateFile

        Write-Host "Stopping IIS Express (process $($IISExpressProcess.ProcessId))..."
        Stop-Process -Id $IISExpressProcess.ProcessId -Force -ErrorAction Ignore
        Wait-Process -Id $IISExpressProcess.ProcessId -Timeout 30 -ErrorAction Ignore
    }
    else {
        # Not running, so there is nothing to bring back; drop a state file a past stop left behind
        Remove-Item -Path $script:IISExpressStateFile -ErrorAction Ignore
    }
}

function Start-D365IISExpress {
    $IsRestartPending = (Test-Path -Path $script:IISExpressStateFile -PathType Leaf) -and
        -not (Get-Process -Name iisexpress -ErrorAction Ignore)

    if ($IsRestartPending) {
        $State = Get-Content -Path $script:IISExpressStateFile -Raw | ConvertFrom-Json

        Write-Host 'Starting IIS Express...'
        Start-Process -FilePath $State.Executable -ArgumentList $State.Arguments -WindowStyle Hidden
    }

    Remove-Item -Path $script:IISExpressStateFile -ErrorAction Ignore
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
    Start-D365IISExpress
}
