# Values for the dev Terraform state backend in Baytex's subscriptions.
# Terraform loads this file automatically; changes are made by pull request and applied at the next dev bootstrap run.

# ----------------------------------------------------------------------------------------------------------------------
# Subscription
# ----------------------------------------------------------------------------------------------------------------------

# Sandbox Entra tenant and the subscription that holds dev state (ME-MngEnvMCAP517100-v-parvkaur-1).
tenant_id       = "f913f484-b59e-49a4-95ce-feddd38dc57a"
subscription_id = "f1c89731-86b0-4cd4-bd2d-f2347c1d62d2"
location        = "canadacentral"

# ----------------------------------------------------------------------------------------------------------------------
# State storage
# ----------------------------------------------------------------------------------------------------------------------

# These three must match TF_STATE_RESOURCE_GROUP, TF_STATE_STORAGE_ACCOUNT and TF_STATE_CONTAINER on the dev-plan GitHub Environment.
# The storage account name is globally unique across Azure.
resource_group_name  = "rg-vkp-dbx-dev-tfstate-cnc-002"
storage_account_name = "stvkpdbxdevtfcnc002"
container_name       = "tfstate"

# Tags applied to the resource group and storage account, matching the tags on the platform resources.
tags = {
  Application        = "AzureDatabricks"
  BusinessUnit       = "BI"
  Environment        = "Dev"
  ManagedBy          = "Terraform"
  Owner              = "Platform Engineering"
  CostCentre         = "VKP-DBX-DEV"
  DataClassification = "Internal"
  Project            = "VKP Terraform Foundations"
}

# ----------------------------------------------------------------------------------------------------------------------
# Access
# ----------------------------------------------------------------------------------------------------------------------

# Object IDs, not application IDs, of operators who need direct access to state.
# The deployment service principal already holds Storage Blob Data Contributor at subscription scope. Example:
#   state_blob_data_contributor_principal_ids = ["00000000-0000-0000-0000-000000000000"]
state_blob_data_contributor_principal_ids = []
