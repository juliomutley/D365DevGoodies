# D365DevGoodies

PowerShell scripts that automate the care and feeding of a **Dynamics 365 Finance & Operations** developer VM: refresh the environment, pull the latest source from TFVC, compile your models, synchronise the database, and bring services back up.

## Prerequisites

- A D365 F&O one-box / cloud-hosted developer VM (Windows Server, elevated PowerShell)
- **Windows PowerShell 5.1** for the scripts that load d365fo.tools (`#Requires -PSEdition Desktop`); do not run those under `pwsh`
- PowerShell modules (the daily scripts install/update them): [`d365fo.tools`](https://github.com/d365collaborative/d365fo.tools), [`dbatools`](https://dbatools.io), `VSSetup`
- Visual Studio 2022 (used to locate `TF.exe` for TFVC operations)
- The [`d365-resources`](https://github.com/) repo cloned **next to** this one (`..\d365-resources`) — `dailyRunAll.ps1` uses its `enableServices.ps1` and `updateApps.ps1`
- Local SQL Server (`.`) hosting `AxDb`

## Quick start

```powershell
# 1. Tell the scripts which models are yours
.\Export-ModelConfig.ps1 -WhatIf     # preview what would be discovered
.\Export-ModelConfig.ps1             # write/merge models.json
.\Get-ModelConfig.ps1                # confirm the resolved lists

# 2. Refresh the environment
.\UpdateDevAll.ps1                   # TF undo/get-latest + compile + DB sync
.\UpdateDevAll.ps1 -NoSync           # compile only (fast; good for smoke tests)
.\dailyRunAll.ps1                    # the full unattended nightly refresh

# 3. Or just rebuild one model
.\Invoke-D365ModelCompile.ps1 -Model "MyModel"
```

## Configuring models

The packages to compile and to TF-undo live in **`models.json`** at the repo root. Both keys are arrays of package **folder** names under `PackagesLocalDirectory` (not the inner model names from the descriptor):

| Key | Meaning |
| --- | --- |
| `ModelsToBuild` | Compiled, and TF-get-latest'd |
| `ModelsToUndoChanges` | TF-undo'd before get-latest; may differ from `ModelsToBuild` (an ISV package can be undo-only) |

- `models.json` is **gitignored** — environment-specific names are never committed. [`models.template.json`](models.template.json) shows the shape.
- If `models.json` is missing, `Get-ModelConfig.ps1` seeds it from the template and **throws**, so a multi-hour compile never starts against placeholder names.
- `Export-ModelConfig.ps1` builds the file by scanning package descriptors for `Customization = Allow` and a non-Microsoft publisher. It merges non-destructively: existing placement is kept, new packages are added and reported, missing ones are warned about. Supports `-WhatIf` and `-Force`.
- Adding an ISV model is an edit to `models.json` only — never to the scripts.

## Orchestrators

| Script | What it does |
| --- | --- |
| `dailyRunAll.ps1` | Full refresh: update PS modules → stop VS/IIS → purge disposable tables → TF undo → get latest → compile all → DB sync → start services → open browser. Logs a transcript to `D:\temp\`, and can refresh OData/DMF entities (`-tenantId`/`-clientId`/`-secretKey`). Built to run unattended. |
| `UpdateDevAll.ps1` | The same TF + compile + sync path without the transcript or entity refresh. `-NoSync` skips TF and the sync (clean + compile only); `-ResetUserData` truncates the user-data tables first. |
| `Invoke-D365ModelCompile.ps1` | Single-model compile (clean → labels → X++ with XRef → best practices). Ignores `models.json`. Throws on failure. |

Switches on `Invoke-D365ModelCompile.ps1` — note the defaults:

| Switch | Default | Effect |
| --- | --- | --- |
| `-DisableDefender` | on | Pauses Defender real-time monitoring for the build and restores it only if it was on |
| `-ShowElapsedTime` | on | Prints elapsed-time lines |
| `-RestartWebHost` | on | Stops IIS Express/AOS app pool before clean-up, restarts the app pool after |
| `-ResetUserData` | off | Truncates disposable user-data tables first |
| `-SkipBestPractice` | off | Skips the best-practice check |

Compilation errors open VS Code on the `.err.xml` file and play a system sound.

## Script catalogue

Every script in the repo, grouped by purpose. **PS 5.1** = needs Windows PowerShell 5.1 (`#Requires -PSEdition Desktop`); **Admin** = needs an elevated session. Scripts marked **hardcoded** carry machine-specific values at the top (paths, drives, URLs) that you should edit before running.

### Orchestrators and build

| Script | Purpose | Notes |
| --- | --- | --- |
| `dailyRunAll.ps1` | Full unattended refresh (see above) | `-ResetUserData`, `-tenantId/-clientId/-secretKey` |
| `UpdateDevAll.ps1` | TF undo/get-latest + compile + sync | `-NoSync`, `-ResetUserData` |
| `Invoke-D365ModelCompile.ps1` | Compile one model: clean → labels → X++ (XRef) → best practices | `-Model` (required), `-ResetUserData`, `-SkipBestPractice`, `-DisableDefender`, `-ShowElapsedTime`, `-RestartWebHost`, `-PackagesLocalDirectory` |
| `Invoke-D365ReportCompile.ps1` | Generate RDL with `reportsc.exe` and publish to SSRS without opening Visual Studio | `-Model` (required), `-ReportName` (default `*`), `-SkipPublish`. Run the model compile first — it reads `<Model>\bin` |
| `syncDB.ps1` | Database sync with SQL memory/MAXDOP and Defender tuned, restored in `finally` | `-DbName` (MAXDOP scope only), `-LogPath` (wiped each run) |
| `Invoke-D365RefreshEntities.ps1` | Opens the `VFFDevEntityListRefresh` menu item in a browser to refresh the data entity list | PS 5.1. `-MenuItem`, `-Url`. Needs the VFFDevTools model deployed and an interactive signed-in browser |

### Model configuration

| Script | Purpose | Notes |
| --- | --- | --- |
| `Get-ModelConfig.ps1` | Loads and validates `models.json`; returns `ModelsToBuild` / `ModelsToUndoChanges` | Seeds from the template and throws if the file is absent |
| `Export-ModelConfig.ps1` | Generates/merges `models.json` from package descriptors | `-WhatIf`, `-Force`, `-Path`, `-PackagesLocalDirectory` |
| `detectCustomizedModels.ps1` | Lists customizable non-Microsoft models | **hardcoded** `K:\AosService\PackagesLocalDirectory` |
| `models.template.json` | Committed placeholder for `models.json` | |
| `ReadXppProject.ps1` | Reads the `Content` entries of an X++ project file and relocates the files they point to | `-ProjectFile`. **Unfinished:** it uses `$destinationDirectory`, which is never defined, so set it before use |

### Source control (TFVC)

| Script | Purpose | Notes |
| --- | --- | --- |
| `Add-D365SourceControl.ps1` | `tf add` untracked XML files for each model (default: `ModelsToBuild`) — typically labels/metadata a compile just produced | `-Models`, `-PackagesLocalDirectory`, `-TfExePath` (pass it in to skip a slow `TF.exe` scan). Skips models with no descriptor |
| `Add-D365TFSourceControl.ps1` | The same idea for a single model, located via the latest VS installation | `-Model` (required) |
| `Remove-ADOWorkitem.ps1` | Closes an Azure DevOps work item with `ClosedStatus = Removed` via the `az` CLI | `-WorkItemId` (required), `-Organization` (**hardcoded** default `MyOrganization`). Runs `az login` |

### Database

| Script | Purpose | Notes |
| --- | --- | --- |
| `Reset-D365UserData.ps1` | Truncates the four disposable user-data tables (`formRunConfiguration`, `SysLastValue`, `SysUserLog`, `sysPersonalization`) | PS 5.1. `-SqlInstance` (`.`), `-DatabaseName` (`AxDb`). `truncate` is unrecoverable — dev only |
| `Prepare-D365DevelopmentDatabaseUpdate.ps1` | Pre-update maintenance: installs modules, deploys Ola Hallengren maintenance, sets Simple recovery/change tracking, repoints batch config, purges batch/staging/temp data, truncates the log | Admin + sysadmin. `-DatabaseName` (`axdb`), `-ShrinkData` (slow). Destructive |
| `importBacPac.ps1` | Imports a `.bacpac` into `AxDB_Newest` with SqlPackage, boosting SQL memory (40%) and MAXDOP during the import | PS 5.1, **hardcoded** `D:\BacPac\PreProd.bacpac`. Runs `disableservices.ps1` first |
| `Get-D365LastestLCSBacpac.ps1` | Downloads the latest LCS database backup to `D:\BacPac` via AzCopy | PS 5.1, **hardcoded** destination |
| `RestoreDatabase.ps1` | Restore a `.bak` into `AxDB_Newest` | **hardcoded** paths/drives; uses **`-OutputScriptOnly`**, so it only prints the T-SQL — remove that flag to actually restore |
| `Rename-AxDbNewest.ps1` | Promotes a restored database to `AxDb`, keeping the old one as `AxDb_old` (dropping any earlier `AxDb_old`) | Admin. `-AxDBNewest` (`AxDbNewest`). Stops services, bounces SQL Server |
| `moveDbFile.ps1` | Shrinks the log, then moves the data and log files to other drives | `-dbName` (`AxDb`). **hardcoded** `G:` data and `H:` log drives |
| `Set-TempDbConfig.ps1` | Sizes TempDB: one data file per core, total 20% of `AxDb` used space, growth disabled | |
| `Enable-DbaDisabledIndex.ps1` | Rebuilds tables that have disabled indexes (`ALTER INDEX ALL … REBUILD`) | `-Database` (required), `-SqlInstance` (`localhost`), supports `-WhatIf` |
| `takeSnapshot.ps1` / `RestoreSnapshot.ps1` | Create / restore a database snapshot of `AxDB` (one-liners over dbatools; restore uses `-Force`) | |
| `Get-BacpacModelHash.ps1` | Defines `Get-BacpacModelHash`: SHA-256 of a bacpac `model.xml` | `-modelXmlPath`. Dot-source it; the file holds only the function |
| `Get-DbNameCompletion.ps1` | Powers Tab-completion of database-name parameters | Not run directly |
| `DatabaseLite/Invoke-D365ImpersonateEmail.ps1` | Replaces every email column value with one address, for anonymising sandboxes | **hardcoded** server, database and credentials (masked placeholders) plus the impersonation address. Destructive |

### Services and web host

| Script | Purpose | Notes |
| --- | --- | --- |
| `D365WebHost.ps1` | Dot-sourced library: `Stop-D365IISExpress`, `Stop/Start-D365AosAppPool`, `Stop/Start-D365WebHost` | No-ops when the host isn't running; the app-pool functions need Admin |
| `disableServices.ps1` | Stops the web hosts and the D365 services and sets them to Disabled | PS 5.1 |
| `enableServices.ps1` | Sets the services to Automatic, starts them plus SSRS and the AOS app pool | PS 5.1. IIS Express is left for Visual Studio to start |
| `stopServices.ps1` | `disableServices.ps1` + kill `Batch`/`xppcAgent` + `iisreset /stop` | |
| `startServices.ps1` | Thin wrapper over `enableServices.ps1` | |
| `RestartServices.ps1` | Disable services → kill `Batch` → restart SQL Server → enable services → `iisreset` | |

### Windows, Visual Studio and VM upkeep

| Script | Purpose | Notes |
| --- | --- | --- |
| `updateApps.ps1` | `choco upgrade all`, updates Visual Studio (`dotnet-vs`), runs `InstallVsExtension.ps1`, then Windows Update | **Reboots** (`-AutoReboot`). Called by `dailyRunAll.ps1` from the sibling `d365-resources` repo |
| `InstallVsExtension.ps1` | Downloads and installs VS extensions into the latest VS (or all VS 2022+ instances) | `-AllVersions` |
| `runWindowsUpdate.ps1` | Installs/updates `PSWindowsUpdate`, then runs Microsoft Update | No auto-reboot |
| `Clear-WindowsUpdateCache.ps1` | Empties `SoftwareDistribution\Download` and reports GB freed | Admin |
| `set-Cypher.ps1` | Adds the TLS ECDHE cipher suites needed to fix Windows Update error `0x80072efe` and PowerShell module installs | PS 5.1, Admin. **Restarts the computer** if it changes anything |
| `Remove-WindowsApp.ps1` | Uninstalls an MSI application by name match, with confirmation | `-SoftwareName` (required). Uses `Win32_Product` |
| `downloadPU.ps1` | Downloads a platform-update zip via AzCopy and extracts it to `D:\` | PS 5.1. **hardcoded** `$SASLink` and `$DestinationFileName` placeholders |
| `get-VMShutdownStatus.ps1` | Connects to Azure and lists VMs without an auto-shutdown schedule | PS 5.1. Installs Az modules; prompts to sign in |
| `UpdateDevEnvWindowsTaskScheduler.xml` | Task Scheduler definition: runs `dailyRunAll.ps1 -verbose` weekly at 11:00, highest privileges | Import it, then fix the **hardcoded** `K:\git\D365DevGoodies` path and the schedule |

### SSRS and web config

| Script | Purpose | Notes |
| --- | --- | --- |
| `Enable-D365RDLSandboxing.ps1` | Adds an `RDLSandboxing` block to `RSReportServer.config` and restarts SSRS | Admin. Idempotent |
| `Remove-D365SSRSReport.ps1` | Deletes `/Dynamics/<report>` from SSRS with `Remove-RsCatalogItem` | `-reportName`. Needs the `ReportingServicesTools` module |
| `changeWebConfig.ps1` | Rewrites the DB server/name and SQL credentials in the AOS `web.config` (backs it up once as `web___DEV___.config`) | `-DBServerDBName` as `server\db`, `-UserName`, `-Password` (all required). **hardcoded** `K:\AosService\WebRoot`. Password is written in plain text |

### `DatabaseLite/`

| Script | Purpose | Notes |
| --- | --- | --- |
| `Import-AzKeyVaultSecret.ps1` | Reads one `;`-delimited CSV per Key Vault (file name = vault name; columns `Name`, `Secret`) and imports each secret | PS 5.1. `-directoryPath`; prompts for Azure sign-in |
| `Invoke-D365ImpersonateEmail.ps1` | See *Database* above | |

## Design notes

- **One definition per concern.** The compile recipe, the user-data table list, the service list, the web-host steps and the model lists each live in exactly one script; callers delegate rather than copy.
- **Failure is a `throw`, not an `exit`**, so an orchestrator can't run on into the sync after a failed build.
- **Defaults are conservative about data loss:** `truncate table` is opt-in (`-ResetUserData`).
- **Cleanup always runs.** Defender, SQL memory/MAXDOP and the AOS app pool are restored in `finally` blocks.
- Scripts reference the sibling repo relatively (`$PSScriptRoot\..\d365-resources`), never by absolute path.

## Warnings

These scripts stop services, kill Visual Studio and IIS, undo TFVC changes, and can truncate tables. Run them on a **development VM only**, and check in or shelve work first.

## License

See [LICENSE](LICENSE).
