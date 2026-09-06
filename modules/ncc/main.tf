resource "databricks_mws_network_connectivity_config" "this" {
  name   = var.name
  region = var.region
}

resource "databricks_mws_ncc_binding" "workspace" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  workspace_id                   = var.workspace_id
}

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

resource "databricks_mws_ncc_private_endpoint_rule" "on_prem" {
  for_each = var.private_link_services

  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = each.value.id
  domain_names                   = each.value.domain_names
}
