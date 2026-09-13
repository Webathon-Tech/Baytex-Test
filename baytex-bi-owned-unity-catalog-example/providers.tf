# ----------------------------------------------------------------------------------------------------------------------
# Databricks providers
# Both authenticate through the signed-in Azure CLI session.
# ----------------------------------------------------------------------------------------------------------------------

# Account level: the metastore assignment.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}

# Workspace level: every Unity Catalog object, created through the platform workspace.
provider "databricks" {
  alias     = "workspace"
  host      = var.workspace_url
  auth_type = "azure-cli"
}
