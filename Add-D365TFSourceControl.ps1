<#
.SYNOPSIS
Adds missing XML files in the specified Dynamics 365 model directory to Azure DevOps using TFS version control.

.DESCRIPTION
This script automates the process of adding missing XML files in a Dynamics 365 model directory to Azure DevOps using TFS (Team Foundation Server) version control. It retrieves the current Dynamics 365 environment settings, navigates to the specified model's directory, locates the TF.exe executable from the latest Visual Studio installation, and executes the TFS "add" command to include all XML files recursively.

.PARAMETER Model
The name of the Dynamics 365 model whose files need to be added to TFS version control. This parameter is mandatory.

.EXAMPLE
.\Add-D365TFSourceControl.ps1 -Model "MyModel"
This example adds all missing XML files in the "MyModel" directory to Azure DevOps using TFS version control.

.NOTES
- Ensure that the Dynamics 365 environment settings are properly configured and accessible.
- The script requires Visual Studio with TFS components installed to locate the TF.exe executable.
- The script uses the `Get-VSSetupInstance` and `Select-VSSetupInstance` cmdlets to find the latest Visual Studio installation.

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Model
)

# Save the current location to restore it later
$currentLocation = Get-Location

# Retrieve Dynamics 365 environment settings
$D365Environment = Get-D365EnvironmentSettings

# Get the local directory for packages from the environment settings
$PackagesLocalDirectory = $D365Environment.Common.BinDir

# Navigate to the specified model's directory
Set-Location "$PackagesLocalDirectory\$Model"

# Locate the installation path of the latest Visual Studio instance
[string] $visualStudioInstallationPath = (Get-VSSetupInstance | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

# Find the TF.exe executable within the Visual Studio installation
$tfExe = (Get-ChildItem $visualStudioInstallationPath -Recurse -Filter "TF.exe" | Select-Object -First 1).FullName

# Define the arguments for the TFS "add" command
$TFArgs = @('add', './*.xml', '/recursive')

# Execute the TF.exe command to add missing XML files
&$tfExe $TFArgs

# Restore the original location
Set-Location $currentLocation