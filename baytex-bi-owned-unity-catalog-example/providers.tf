provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}

provider "databricks" {
  alias     = "workspace"
  host      = var.workspace_url
  auth_type = "azure-cli"
}
