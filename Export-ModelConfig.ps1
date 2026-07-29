<#
.SYNOPSIS
Generates or refreshes models.json by discovering customizable packages in the packages local directory.

.DESCRIPTION
Walks every `<package>\Descriptor\*.xml` under the packages local directory and keeps the packages
whose descriptor marks them customizable and non-Microsoft (`Customization = Allow` and
`Publisher <> Microsoft Corporation`) -- the same test Detect-CustomizedModels uses. The package
FOLDER name is written, since that is what the orchestrator scripts resolve paths against.

By default the write is a merge and is never destructive:

  * packages already listed keep their exact current placement, so an undo-only entry stays
    undo-only;
  * newly discovered packages are added to both lists and reported, so you can prune the ones you
    do not want compiled;
  * entries in the file with no matching folder on disk are kept, but warned about.

Use -Force to discard that curation and rewrite both lists purely from what is on disk.

.PARAMETER PackagesLocalDirectory
Packages local directory to scan. Defaults to the D365 environment settings, falling back to
`K:\AosService\PackagesLocalDirectory`.

.PARAMETER Path
Config file to write. Defaults to `models.json` beside this script.

.PARAMETER Force
Rewrite both lists from discovery instead of merging, discarding any manual curation.

.EXAMPLE
.\Export-ModelConfig.ps1 -WhatIf

Previews the changes without writing.

.EXAMPLE
.\Export-ModelConfig.ps1

Merges newly discovered packages into the existing models.json.

.EXAMPLE
.\Export-ModelConfig.ps1 -Force

Regenerates models.json from disk, dropping manual edits.

.NOTES
- d365fo.tools is optional; without it the fallback packages local directory is used.
- models.json is gitignored -- environment-specific model names stay off the repository.
- Companion: Get-ModelConfig.ps1 reads the file the orchestrator scripts consume.

#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string] $PackagesLocalDirectory,

    [Parameter(Mandatory = $false)]
    [string] $Path = (Join-Path $PSScriptRoot 'models.json'),

    [Parameter(Mandatory = $false)]
    [switch] $Force
)

#region resolve the packages local directory
if (-not $PackagesLocalDirectory) {
    $BinDir = $null
    if (Get-Command Get-D365EnvironmentSettings -ErrorAction SilentlyContinue) {
        # Throws on a machine where the D365 configuration assemblies are not loadable (e.g. under
        # PowerShell 7); the fallback below is good enough, so do not let it surface as an error.
        try { $BinDir = (Get-D365EnvironmentSettings).Common.BinDir }
        catch { Write-Verbose "Get-D365EnvironmentSettings failed, using the fallback path: $($_.Exception.Message)" }
    }
    $PackagesLocalDirectory = if ($BinDir) { $BinDir } else { 'K:\AosService\PackagesLocalDirectory' }
}

if (-not (Test-Path -LiteralPath $PackagesLocalDirectory)) {
    throw "Packages local directory '$PackagesLocalDirectory' not found. Pass -PackagesLocalDirectory explicitly."
}

Write-Verbose "Scanning $PackagesLocalDirectory"
#endregion

#region discover customizable, non-Microsoft packages
$Discovered = [System.Collections.Generic.List[string]]::new()

foreach ($Dir in Get-ChildItem -LiteralPath $PackagesLocalDirectory -Directory | Sort-Object Name) {
    $DescriptorDir = Join-Path $Dir.FullName 'Descriptor'
    if (-not (Test-Path -LiteralPath $DescriptorDir)) { continue }

    foreach ($Descriptor in Get-ChildItem -LiteralPath $DescriptorDir -Filter '*.xml' -File -ErrorAction SilentlyContinue) {
        try {
            [xml] $XmlContent = Get-Content -LiteralPath $Descriptor.FullName -Raw -ErrorAction Stop
        }
        catch {
            Write-Warning "Skipping unreadable descriptor '$($Descriptor.FullName)': $($_.Exception.Message)"
            continue
        }

        if (($XmlContent.AxModelInfo.Customization -eq 'Allow') -and
            ($XmlContent.AxModelInfo.Publisher -ne 'Microsoft Corporation')) {
            # The folder name, not AxModelInfo.ModelModule -- callers path off the folder.
            if (-not $Discovered.Contains($Dir.Name)) { $Discovered.Add($Dir.Name) }
            break
        }
    }
}

if ($Discovered.Count -eq 0) {
    throw "No customizable non-Microsoft packages found under '$PackagesLocalDirectory'. Nothing to write."
}

Write-Verbose "Discovered $($Discovered.Count) customizable package(s)."
#endregion

#region merge against the existing file
$ExistingBuild = @()
$ExistingUndo = @()
$FileExists = Test-Path -LiteralPath $Path
$IsMerge = (-not $Force) -and $FileExists

# Read the existing file even under -Force. It is not used for the write then, but it is the only
# way to report what -Force is about to discard -- and since discovery misses packages that have no
# descriptor or are sealed, that list can contain entries you still need.
if ($FileExists) {
    try {
        $Existing = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        if ($IsMerge) {
            throw "Existing model config '$Path' is not valid JSON, refusing to merge into it: $($_.Exception.Message)"
        }
        Write-Warning "Existing model config '$Path' is not valid JSON; -Force will overwrite it wholesale."
        $Existing = $null
    }
    if ($Existing) {
        $ExistingBuild = @($Existing.ModelsToBuild) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $ExistingUndo = @($Existing.ModelsToUndoChanges) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
}

$Known = @($ExistingBuild) + @($ExistingUndo) | Select-Object -Unique
$Added = @($Discovered | Where-Object { $Known -notcontains $_ })
$Unchanged = @($Discovered | Where-Object { $Known -contains $_ })

# Configured entries the descriptor walk did not surface. These are NOT interchangeable, so keep
# them apart: descriptor-based discovery legitimately misses valid packages (no Descriptor\*.xml at
# all, Customization=DoNotAllow on a sealed ISV package, or a Microsoft publisher), and those still
# compile fine. Only a genuinely absent folder is a problem -- the orchestrators Test-Path it and
# exit. Warning about both would push you to prune entries that are perfectly correct.
$NotDiscovered = @($Known | Where-Object { -not $Discovered.Contains($_) })
$FolderMissing = @($NotDiscovered | Where-Object { -not (Test-Path -LiteralPath (Join-Path $PackagesLocalDirectory $_)) })
$NotAutoDiscovered = @($NotDiscovered | Where-Object { Test-Path -LiteralPath (Join-Path $PackagesLocalDirectory $_) })

if (-not $IsMerge) {
    # Fresh generation: both lists start identical, prune by hand afterwards.
    $NewBuild = @($Discovered)
    $NewUndo = @($Discovered)
}
else {
    # Existing membership is preserved exactly; only genuinely new packages join both lists.
    $NewBuild = @($ExistingBuild) + $Added
    $NewUndo = @($ExistingUndo) + $Added
}
#endregion

#region report
Write-Host ""
Write-Host "*** Model config: $Path ***" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host ""
Write-Host "Packages local directory : $PackagesLocalDirectory"
Write-Host "Mode                     : $(if ($Force) { 'overwrite (-Force)' } elseif ($IsMerge) { 'merge' } else { 'create' })"
Write-Host ""

if ($Added.Count -gt 0) {
    Write-Host "Added to both lists ($($Added.Count)):" -ForegroundColor Cyan
    $Added | ForEach-Object { Write-Host "  + $_" -ForegroundColor Cyan }
    Write-Host "  Review these -- remove any you do not want compiled." -ForegroundColor Cyan
}
else {
    Write-Host "Added to both lists: none" -ForegroundColor Cyan
}

Write-Host "Already configured ($($Unchanged.Count)): $($Unchanged -join ', ')"

if ($NotAutoDiscovered.Count -gt 0) {
    # Informational, not a problem: these compile fine, they just cannot be auto-discovered.
    Write-Host ("Configured, present, not auto-discoverable ({0}): {1}" -f `
            $NotAutoDiscovered.Count, ($NotAutoDiscovered -join ', '))
    Write-Host "  (no Descriptor\*.xml, Customization=DoNotAllow, or a Microsoft publisher -- keep them.)"
}

if ($FolderMissing.Count -gt 0) {
    Write-Warning ("Configured but the folder is MISSING under '$PackagesLocalDirectory' " +
        "($($FolderMissing.Count)): $($FolderMissing -join ', '). Kept in the file, but the " +
        "orchestrator scripts will abort on these -- get them from source control or remove them.")
}

if ($Force -and $NotDiscovered.Count -gt 0) {
    Write-Warning ("-Force will DROP $($NotDiscovered.Count) configured package(s) that discovery " +
        "did not find: $($NotDiscovered -join ', '). Re-run without -Force to keep them.")
}
Write-Host ""
#endregion

#region write
$Output = [pscustomobject] @{
    ModelsToBuild       = [string[]] $NewBuild
    ModelsToUndoChanges = [string[]] $NewUndo
}

if ($PSCmdlet.ShouldProcess($Path, 'Write model config')) {
    $Output | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "Wrote $($NewBuild.Count) model(s) to build, $($NewUndo.Count) to undo." -ForegroundColor Green
}
#endregion
