<#
.SYNOPSIS
Loads the list of D365 packages to compile and to undo, from models.json.

.DESCRIPTION
Single source of truth for the model lists the orchestrator scripts (dailyRunAll.ps1, UpdateDev.ps1,
UpdateDevAll.ps1, UpdateDevNoSync.ps1) used to hardcode individually. Returns an object with two
string arrays, `ModelsToBuild` and `ModelsToUndoChanges`.

The names are package/module FOLDER names under the packages local directory -- the value the
callers `Test-Path` and `Set-Location` against -- not the inner model names from the descriptor.

`models.json` is gitignored so environment-specific model names never reach the repository. When it
is absent this script seeds one from `models.template.json` and then throws: the template holds
placeholder names, and continuing would send a multi-hour compile at models that do not exist.
Either edit the seeded file or run Export-ModelConfig.ps1 to generate it from disk.

This is a script rather than a dot-sourced function so callers get the value back without the
script leaking names into their scope:

    $ModelConfig = & "$PSScriptRoot\Get-ModelConfig.ps1"

.PARAMETER Path
Config file to read. Defaults to `models.json` beside this script.

.EXAMPLE
$ModelConfig = & "$PSScriptRoot\Get-ModelConfig.ps1"
$Models2Compile = $ModelConfig.ModelsToBuild

.EXAMPLE
(& .\Get-ModelConfig.ps1).ModelsToUndoChanges

.NOTES
- No external module dependencies; targets Windows PowerShell 5.1 (no ConvertFrom-Json -AsHashtable).
- Unknown keys in the JSON (such as `_comment`) are ignored.
- Companion: Export-ModelConfig.ps1 generates/refreshes models.json from PackagesLocalDirectory.

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $Path = (Join-Path $PSScriptRoot 'models.json')
)

$TemplatePath = Join-Path $PSScriptRoot 'models.template.json'

if (-not (Test-Path -LiteralPath $Path)) {
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "Model config '$Path' not found, and no template to seed it from at '$TemplatePath'."
    }

    Copy-Item -LiteralPath $TemplatePath -Destination $Path
    throw ("Model config '$Path' was missing, so it has been seeded from the template. " +
        "It still holds placeholder model names -- edit it, or run Export-ModelConfig.ps1 to " +
        "generate it from the packages local directory, then re-run.")
}

try {
    $Config = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Model config '$Path' is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $Config) {
    throw "Model config '$Path' is empty."
}

# Validate both keys up front so a typo surfaces here rather than as an empty loop three hours in.
$Validated = @{}
foreach ($Key in 'ModelsToBuild', 'ModelsToUndoChanges') {
    if ($null -eq $Config.PSObject.Properties[$Key]) {
        throw "Model config '$Path' is missing the required key '$Key'."
    }

    # @() keeps a single-element JSON array an array; without it the value unrolls to a bare
    # string and the callers' ForEach-Object would iterate its characters.
    $Values = @($Config.$Key)

    if ($Values.Count -eq 0) {
        throw "Model config '$Path' has an empty '$Key'. List at least one package folder name."
    }

    if ($Values | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
        throw "Model config '$Path' has a blank entry in '$Key'."
    }

    $Validated[$Key] = [string[]] $Values
}

[pscustomobject] @{
    ModelsToBuild       = $Validated['ModelsToBuild']
    ModelsToUndoChanges = $Validated['ModelsToUndoChanges']
}
