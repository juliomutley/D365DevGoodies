<#
.SYNOPSIS
    Updates the state of a specified Azure DevOps work item to "Closed".

.DESCRIPTION
    This script logs into Azure, configures the Azure DevOps organization, 
    and updates the state of a specified work item to "Closed" with the 
    "Microsoft.VSTS.CodeReview.ClosedStatus" field set to "Removed".

.PARAMETER WorkItemId
    The ID of the work item to update. This parameter is mandatory.

.PARAMETER OrganizationUrl
    The URL of the Azure DevOps organization. This parameter is optional. 
    If not provided, the default value "https://dev.azure.com/MyOrganization/" will be used.

.EXAMPLE
    .\script.ps1 -WorkItemId 53500
    Logs into Azure, configures the Azure DevOps organization, and updates 
    the work item with ID 53500 to "Closed".

.EXAMPLE
    .\script.ps1 -WorkItemId 53500 -OrganizationUrl "https://dev.azure.com/MyOrganization/"
    Logs into Azure, configures the specified Azure DevOps organization, and updates 
    the work item with ID 53500 to "Closed".

.NOTES
    Ensure you have the Azure CLI installed and authenticated before running this script.
#>

param (
    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $false)]
    [string]$OrganizationUrl = "https://dev.azure.com/MyOrganization/"
)

write-host "Logging into Azure..."
az login --output none --allow-no-subscriptions
write-host "Configuring Azure DevOps organization..."
az DevOps configure --defaults organization=$OrganizationUrl --output none
write-host "Updating work item with ID $WorkItemId to Closed..."
az boards work-item update --id $WorkItemId --state "Closed" --fields "Microsoft.VSTS.CodeReview.ClosedStatus=Removed" --output none
write-host "Work item with ID $WorkItemId has been updated to Closed."