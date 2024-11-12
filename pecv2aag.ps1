###### If MFA is NOT required during login: Run "az login" 
###### If MFA is REQUIRED: "az login --tenant <tenantId>"
# SRC = Support Request Contributor
# AAG = Admin Agents Group

# Function to check if Azure CLI is installed
function CheckPrerequisites {
    Write-Host "Checking prerequisites." -ForegroundColor Cyan
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host "Azure CLI is required but could not be found: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "Azure CLI found." -ForegroundColor Green
    }
}

# Function to verify RBAC & Entra ID(AAD) roles for the signed-in user
function VerifySignedInUserRoles {
    Write-Host "Retrieving Signed-In Users ObjectId."
    $SignedInUserId = az ad signed-in-user show --query id -o tsv

    if (-not $SignedInUserId) {
        Write-Host "User objectId not found. Exiting."
        exit 1
    }
    else {
        az role assignment list --assignee $SignedInUserId --all -o table
    }
}

# Function to initialize variables
function AdminAgentGroupVariable {
    $global:adminAgentsGroupId = "d2bbd7ab-3014-484e-9690-fbd3b3ac19dc"
}

# Function to retrieve subscription and management group information
function RetrieveSubscriptionAndManagementGroupInfo {
    # Retrieve the subscription ID
    $subscriptionId = az account show --query "id" -o tsv
    
    # Retrieve all management group names
    $mgmtGroupNames = az account management-group list --query "[].displayName" -o tsv
    
    # Retrieve the root management group ID
    $rootMgmtGroupId = az account management-group list --query "[0].id" -o tsv
    
    # Output subscription information
    Write-Host "Subscription" -ForegroundColor Yellow
    Write-Host "------------" -ForegroundColor Cyan
    Write-Host "Subscription ID: $subscriptionId" -ForegroundColor White
    Write-Host ""
    
    # Output management group information
    Write-Host "Management Groups" -ForegroundColor Yellow
    Write-Host "-----------------" -ForegroundColor Cyan
    foreach ($mgmtGroupName in $mgmtGroupNames) {
        Write-Host "$mgmtGroupName" -ForegroundColor White
    }
    Write-Host ""
    
    # Output root management group information
    Write-Host "Root Management Group" -ForegroundColor Yellow
    Write-Host "---------------------" -ForegroundColor Cyan
    Write-Host "$rootMgmtGroupId" -ForegroundColor White
    Write-Host ""
}

# Function to format the management group or subscription name to proper scope
function FormatScope {
    param (
        [string]$scopeName,
        [string]$type
    )

    if ($type -eq "mgmtGroup") {
        # Convert management group name to proper scope
        $mgmtGroupId = az account management-group show --name $scopeName --query id -o tsv
        return $mgmtGroupId
    }
    elseif ($type -eq "subscription") {
        # Convert subscription name to proper scope
        $subscriptionId = az account subscription list --query "[?displayName=='$scopeName'].id" -o tsv
        return "/subscriptions/$subscriptionId"
    }
}

# Function to assign roles to SPN based on scope selection
function AssignSRCRole {
    Write-Host "Assigning roles to the Service Principal." -ForegroundColor Cyan

    $scopes = @()
    
    #### Management Group selection
    $useDifferentMgmtScopes = Read-Host "Assign SRC role to non-root management group(s)? (y/n)"
    if ($useDifferentMgmtScopes -eq "y" -or $useDifferentMgmtScopes -eq "yes") {
        $selectedMgmtGroups = Read-Host "Enter management group names (comma-separated)" # e.g., "mgmtgroup1, mgmtgroup2"
        if ($selectedMgmtGroups) {
            $additionalScopes = $selectedMgmtGroups -split ',' | ForEach-Object {
                FormatScope $_.Trim() "mgmtGroup"
            }
            $scopes += $additionalScopes
        }

    }
    elseif ($useDifferentMgmtScopes -eq "n" -or $useDifferentMgmtScopes -eq "no") {
        $assignToSub = Read-Host "Do you want to apply the role at the subscription level? (y/n)"
        if ($assignToSub -eq "y" -or $assignToSub -eq "yes") {
            $selectedSubNames = Read-Host "Enter the subscription names (comma-separated)" # e.g., "sub1, sub2"
            if ($selectedSubNames) {
                $selectedSubs = $selectedSubNames -split ',' | ForEach-Object {
                    FormatScope $_.Trim() "subscription"
                }
                $scopes += $selectedSubs
            }
            else {
                Write-Host "No valid subscription names provided. Exiting." -ForegroundColor Red
                exit 1
            }
        }
        elseif ($assignToSub -eq "n" -or $assignToSub -eq "no") {
            # If "no" for both management group and subscription, default to root management group
            $rootMgmtGroupId = az account management-group list --query "[0].id" -o tsv
            $scopes += $rootMgmtGroupId
        }
        else {
            Write-Host "Invalid input for subscription selection. Exiting." -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "Invalid input for scope selection. Exiting." -ForegroundColor Red
        exit 1
    }

    # Assign the roles to the specified scopes
    foreach ($scope in $scopes) {
        if ($scope -eq $rootMgmtGroupId) {
            $level = "Root Management Group"
        }
        elseif ($scope -like "/providers/Microsoft.Management/managementGroups*") {
            $level = "Management Group"
        }
        else {
            $level = "Subscription"
        }
    
        Write-Host "Assigning the Support Request Contributor role at the $level level." -ForegroundColor Cyan
    
        az role assignment create `
            --role "Support Request Contributor" `
            --assignee-object-id $spnObjectId `
            --assignee-principal-type "ForeignGroup" `
            --scope $scope

        Write-Host "Support Request Contributor role assigned at the $level level." -ForegroundColor Green
    }
}

# Retrieve & verify role assignment
function VerifyAAGRole {
    Write-Host "Retrieve the ATEA SPN roles in the customer tenant." -ForegroundColor Magenta
    az role assignment list --assignee $adminAgentsGroupId --all -o table   
}

# Main script execution
CheckPrerequisites
VerifySignedInUserRoles
AdminAgentGroupVariable
RetrieveSubscriptionAndManagementGroupInfo
CreateOrRetrieveSPN
AssignSRCRole
VerifyAAGRole