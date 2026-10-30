# Values for the test Terraform state backend in Baytex's subscriptions.
# Terraform loads this file automatically; changes are made by pull request and applied at the next test bootstrap run.

# ----------------------------------------------------------------------------------------------------------------------
# Subscription
# ----------------------------------------------------------------------------------------------------------------------

# Baytex Entra tenant and the subscription that holds test state (SUB-BTE-CAN-DATA-TEST).
tenant_id       = "9a6302b1-6a51-4f41-ad6b-ad23218c074d"
subscription_id = "7ba1d46e-61db-4e7e-9f60-a7a5417bdd04"
location        = "canadacentral"

# ----------------------------------------------------------------------------------------------------------------------
# State storage
# ----------------------------------------------------------------------------------------------------------------------

# These three must match TF_STATE_RESOURCE_GROUP, TF_STATE_STORAGE_ACCOUNT and TF_STATE_CONTAINER on the test-plan GitHub Environment.
# The storage account name is globally unique across Azure.
resource_group_name  = "rg-bte-dbx-test-tfstate-cnc-002"
storage_account_name = "stbtedbxtesttfcnc002"
container_name       = "tfstate"

# Tags applied to the resource group and storage account, matching the tags on the platform resources.
tags = {
  Application        = "AzureDatabricks"
  BusinessUnit       = "BI"
  Environment        = "Test"
  ManagedBy          = "Terraform"
  Owner              = "Baytex Infrastructure"
  CostCentre         = "BTX-DBX-TEST"
  DataClassification = "Internal"
  Project            = "Baytex Terraform Foundations"
}

# ----------------------------------------------------------------------------------------------------------------------
# Access
# ----------------------------------------------------------------------------------------------------------------------

# Object IDs, not application IDs, of operators who need direct access to state.
# The deployment service principal already holds Storage Blob Data Contributor at subscription scope. Example:
#   state_blob_data_contributor_principal_ids = ["00000000-0000-0000-0000-000000000000"]
state_blob_data_contributor_principal_ids = []
