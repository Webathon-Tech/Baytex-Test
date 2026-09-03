output "network_connectivity_config_id" {
  value = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
}

output "binding_id" { value = databricks_mws_ncc_binding.workspace.id }

output "private_endpoint_rules" {
  value = merge(
    {
      storage_blob = {
        rule_id          = databricks_mws_ncc_private_endpoint_rule.storage_blob.rule_id
        endpoint_name    = databricks_mws_ncc_private_endpoint_rule.storage_blob.endpoint_name
        connection_state = databricks_mws_ncc_private_endpoint_rule.storage_blob.connection_state
      }
      storage_dfs = {
        rule_id          = databricks_mws_ncc_private_endpoint_rule.storage_dfs.rule_id
        endpoint_name    = databricks_mws_ncc_private_endpoint_rule.storage_dfs.endpoint_name
        connection_state = databricks_mws_ncc_private_endpoint_rule.storage_dfs.connection_state
      }
    },
    {
      for key, rule in databricks_mws_ncc_private_endpoint_rule.on_prem : key => {
        rule_id          = rule.rule_id
        endpoint_name    = rule.endpoint_name
        connection_state = rule.connection_state
      }
    }
  )
}
