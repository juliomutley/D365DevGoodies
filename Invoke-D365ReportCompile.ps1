<#
.SYNOPSIS
Generates the RDL files of a Dynamics 365 Finance & Operations model's reports with `reportsc.exe` and
publishes them to SQL Server Reporting Services, without opening Visual Studio.

.DESCRIPTION
What Visual Studio does at the start of a project build (its BuildTask calls the report generator in
process), as a script:

  1. Generates the RDL files with `reportsc.exe`, the standalone report compiler that ships in the
     packages local directory `bin` folder. Each design of a report becomes one file,
     `<Model>\Reports\<ReportName>.<DesignName>.rdl`. Measured on 2026-11-04 with VFFCustSalesOrderStatus:
     the output is identical to Visual Studio's, apart from one random `rd:DataSourceID` GUID.
  2. Publishes the RDL files that were just written with `Publish-D365SsrsReport` from d365fo.tools,
     unless -SkipPublish is given.

Both steps are checked: `reportsc.exe` diagnostics are read from its XML log (errors and fatal errors print
and throw), the script confirms RDL files were written, and the SSRS deployment log is read afterwards.
`Publish-D365SsrsReport` reports its own failures by logging and returning, never by throwing, so the log
is the only place its failure shows. A failure throws, so a caller looping over several models stops on the
first bad one.

Only reports are processed: no label generation, no X++ compile, no best-practice run, no database sync.
Run `Invoke-D365ModelCompile.ps1` first when the X++ changed, because `reportsc.exe` reads the compiled
model from `<Model>\bin` (-compiledILFolder).

.PARAMETER Model
Name of the D365 model (the package folder name under the packages local directory). Mandatory.

.PARAMETER ReportName
Report names (AxReport object names, not design names) to generate and publish. Defaults to `*`, every
report of the model. Example: `VFFCustSalesOrderStatus` produces `VFFCustSalesOrderStatus.ByCust.rdl`.

.PARAMETER SkipPublish
Generates the RDL files only. Use it to check what `reportsc.exe` produces, or when publishing is done
another way (for example Visual Studio's own deploy).

.EXAMPLE
.\Invoke-D365ReportCompile.ps1 -Model "VFF" -ReportName "VFFCustSalesOrderStatus"

Generate the RDL files of one report and publish them.

.EXAMPLE
.\Invoke-D365ReportCompile.ps1 -Model "VFF" -ReportName "VFFCustSalesOrderStatus", "VFFCustSalesOpenLines_NA" -SkipPublish

Generate two reports, publish nothing.

.NOTES
- Run it with Windows PowerShell 5.1 (`powershell.exe`), never PowerShell 7 (`pwsh`): d365fo.tools loads
  .NET Framework assemblies (see the vff-build skill), and under `pwsh` the script cannot resolve its D365
  paths and fails with misleading errors such as "Model VFF not found" and "\bin\...dll path wasn't found".
  A `#Requires -PSEdition Desktop` line makes `pwsh` refuse to start the script with a clear message.
  From a `pwsh` or VS Code terminal:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Invoke-D365ReportCompile.ps1' -Model VFF -ReportName <Report>"`
- Fixed for the one-box dev machine: packages in `K:\AosService\PackagesLocalDirectory`, SSRS at `127.0.0.1`.
- Run elevated in practice: the packages local directory is not user-writable.
- `reportsc.exe` rewrites the RDL files of the reports it is given and nothing else. Logs are written to
  the model root: `Dynamics.AX.<Model>.reportsc.log` and `.reportsc.xml`. The deployment log is
  `C:\temp\d365fo.tools\AxReportDeployment.log`.
#>

#Requires -PSEdition Desktop

param(
    [Parameter(Mandatory = $true)]
    [string] $Model,

    [Parameter(Mandatory = $false)]
    [string[]] $ReportName = '*',

    [Parameter(Mandatory = $false)]
    [switch] $SkipPublish
)

#region variables
$ActionFGColor = "White"
$ActionBGColor = "DarkGreen"
$ErrorFGColor = "White"
$ErrorBGColor = "Red"
$FinishedFGColor = "Green"
$ExecutionStartTime = $(Get-Date)

# One-box development machine: the packages and SSRS are always local
$PackagesLocalDirectory = 'K:\AosService\PackagesLocalDirectory'
$ReportServerIp = '127.0.0.1'

$ReportCompilerPath = Join-Path $PackagesLocalDirectory 'bin\reportsc.exe'
$ModelRoot = Join-Path $PackagesLocalDirectory $Model
$ReportsFolder = Join-Path $ModelRoot 'Reports'
$CompilerLogFile = Join-Path $ModelRoot "Dynamics.AX.$Model.reportsc.log"
$CompilerXmlLogFile = Join-Path $ModelRoot "Dynamics.AX.$Model.reportsc.xml"
$DeploymentLogFile = 'C:\temp\d365fo.tools\AxReportDeployment.log'
#endregion variables

#region Functions
function Write-ElapsedTime($TaskStartTime) {
    $ElapsedTimeFGColor = "Cyan"
    $ElapsedTime = New-TimeSpan $TaskStartTime $(Get-Date)
    Write-Host "Elapsed time:$($ElapsedTime.ToString("hh\:mm\:ss"))" -ForegroundColor $ElapsedTimeFGColor
}

function Write-Finished($StartTime) {
    Write-Host "Finished!" -ForegroundColor $FinishedFGColor
    Write-ElapsedTime $StartTime
}
#endregion Functions

$ModelToServe = Get-D365Model $Model
if ($ModelToServe) {
    $IsReportCompilerFound = Test-Path -Path $ReportCompilerPath -PathType Leaf

    if ($IsReportCompilerFound) {
        $IsPublishPossible = $SkipPublish -or ($PSVersionTable.PSEdition -eq 'Desktop')

        if ($IsPublishPossible) {
            Write-Host ""
            Write-Host "*** Generating RDL files for model $Model... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
            Write-Host ""

            $TaskStartTime = $(Get-Date)

            # Stale logs from an earlier run would be mistaken for this run's diagnostics
            Remove-Item -Path $CompilerLogFile, $CompilerXmlLogFile -ErrorAction Ignore

            # The report compiler reads the compiled model from the model's bin folder
            $CompilerArguments = @(
                "-metadata=$PackagesLocalDirectory",
                "-modelmodule=$Model",
                "-name=$($ReportName -join ',')",
                "-output=$ReportsFolder",
                "-LabelsPath=$PackagesLocalDirectory",
                "-compiledILFolder=$(Join-Path $ModelRoot 'bin')",
                "-log=$CompilerLogFile",
                "-xmllog=$CompilerXmlLogFile"
            )

            & $ReportCompilerPath @CompilerArguments | Out-Host
            $CompilerExitCode = $LASTEXITCODE

            # Errors and fatal errors in the XML log mean report generation failed; show them and throw
            $CompilerErrors = @()
            if (Test-Path -Path $CompilerXmlLogFile -PathType Leaf) {
                $CompilerErrors = @(([xml](Get-Content -Path $CompilerXmlLogFile -Raw)).Diagnostics.Items.Diagnostic |
                    Where-Object { $_.Severity -in 'Error', 'Fatal' })
            }

            $GeneratedRdlFiles = @(Get-ChildItem -Path $ReportsFolder -Filter '*.rdl' -ErrorAction Ignore |
                Where-Object { $_.LastWriteTime -ge $TaskStartTime })

            $IsGenerationSuccessful = ($CompilerExitCode -eq 0) -and ($CompilerErrors.Count -eq 0) -and ($GeneratedRdlFiles.Count -gt 0)

            if ($IsGenerationSuccessful) {
                Write-Host "Generated $($GeneratedRdlFiles.Count) RDL file(s) in ${ReportsFolder}:"
                $GeneratedRdlFiles | ForEach-Object { Write-Host "  $($_.Name)" }
                Write-Finished $TaskStartTime
            }
            else {
                Write-Host ""
                Write-Host "*** Report generation error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
                Write-Host ""
                $CompilerErrors | ForEach-Object { Write-Host "$($_.Severity): $($_.Path) $($_.Message)" }
                [system.media.systemsounds]::Hand.play()
                throw "Report generation error on model $Model (exit code $CompilerExitCode, $($CompilerErrors.Count) error(s), $($GeneratedRdlFiles.Count) RDL file(s) written), see $CompilerLogFile"
            }

            if (-not $SkipPublish) {
                Write-Host ""
                Write-Host "*** Publishing reports of model $Model to SSRS... ***" -ForegroundColor $ActionFGColor -BackgroundColor $ActionBGColor
                Write-Host ""

                $TaskStartTime = $(Get-Date)

                # Publish-D365SsrsReport takes <ReportName>.<DesignName>, the RDL file name without its extension
                $DeployedReportNames = @($GeneratedRdlFiles | ForEach-Object { $_.BaseName })

                $DeploymentLogLinesBefore = 0
                if (Test-Path -Path $DeploymentLogFile -PathType Leaf) {
                    $DeploymentLogLinesBefore = @(Get-Content -Path $DeploymentLogFile).Count
                }

                Publish-D365SsrsReport -Module $Model -ReportName $DeployedReportNames `
                    -PackageDirectory $PackagesLocalDirectory -ToolsBasePath $PackagesLocalDirectory `
                    -ReportServerIp $ReportServerIp `
                    -LogFile $DeploymentLogFile

                # The cmdlet logs its failures and returns without throwing, so read what it wrote this run
                $DeploymentLogLines = @()
                if (Test-Path -Path $DeploymentLogFile -PathType Leaf) {
                    $DeploymentLogLines = @(Get-Content -Path $DeploymentLogFile | Select-Object -Skip $DeploymentLogLinesBefore)
                }

                # Failures seen in the log (2026-11-04, SSRS rejecting an RDL value): a "Publish-AXReport :" error line,
                # a SoapException, "Something went wrong", and a result-table row whose status is Error
                $DeploymentFailures = @($DeploymentLogLines | Where-Object { $_ -match '(?i)(\b(exception|failed|failure)\b|Publish-AXReport\s*:|went wrong|\sError\s*$)' })

                if ($DeploymentFailures.Count -eq 0) {
                    Write-Host "Published $($DeployedReportNames.Count) report design(s); deployment log: $DeploymentLogFile"
                    Write-Finished $TaskStartTime
                }
                else {
                    Write-Host ""
                    Write-Host "*** SSRS deployment error on model $Model... ***" -ForegroundColor $ErrorFGColor -BackgroundColor $ErrorBGColor
                    Write-Host ""
                    $DeploymentFailures | ForEach-Object { Write-Host $_ }
                    [system.media.systemsounds]::Hand.play()
                    throw "SSRS deployment error on model $Model, see $DeploymentLogFile"
                }
            }

            Write-ElapsedTime $ExecutionStartTime
        }
        else {
            throw "Publishing needs Windows PowerShell 5.1 (d365fo.tools loads .NET Framework assemblies); this is $($PSVersionTable.PSEdition). Use powershell.exe, or pass -SkipPublish."
        }
    }
    else {
        throw "Report compiler not found: $ReportCompilerPath"
    }
}
else {
    throw "Model $Model not found in $PackagesLocalDirectory"
}
