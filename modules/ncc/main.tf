# ----------------------------------------------------------------------------------------------------------------------
# Network Connectivity Configuration module
# Gives Databricks serverless compute private access to the data storage account and to each on-premises destination behind a Private Link Service.
# These are Databricks account-level resources, so the module uses the account-level databricks provider.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# NCC and workspace binding
# ----------------------------------------------------------------------------------------------------------------------

# One NCC per environment, because a workspace can be bound to only one NCC.
resource "databricks_mws_network_connectivity_config" "this" {
  name   = var.name
  region = var.region
}

resource "databricks_mws_ncc_binding" "workspace" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  workspace_id                   = var.workspace_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoint rules
# ----------------------------------------------------------------------------------------------------------------------

# Each rule makes Databricks create a private endpoint from its serverless network to the target resource.
# The endpoint connection arrives as Pending on the target and must be approved before serverless compute can use it.

# Data storage account: one rule for blob and one for dfs.
resource "databricks_mws_ncc_private_endpoint_rule" "storage_blob" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = var.storage_account_id
  group_id                       = "blob"
}

resource "databricks_mws_ncc_private_endpoint_rule" "storage_dfs" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = var.storage_account_id
  group_id                       = "dfs"
}

# On-premises destinations: one rule per Private Link Service.
# domain_names makes serverless compute resolve each destination's FQDN to its private endpoint.
resource "databricks_mws_ncc_private_endpoint_rule" "on_prem" {
  for_each = var.private_link_services

  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = each.value.id
  domain_names                   = each.value.domain_names
}
