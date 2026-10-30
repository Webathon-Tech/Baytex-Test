# ----------------------------------------------------------------------------------------------------------------------
# Databricks provider
# Authenticates through the signed-in Azure CLI session.
# ----------------------------------------------------------------------------------------------------------------------

# Workspace level: every Unity Catalog object, created through the platform workspace.
provider "databricks" {
  alias     = "workspace"
  host      = var.workspace_url
  auth_type = "azure-cli"
}
