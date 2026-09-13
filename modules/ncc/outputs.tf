# ----------------------------------------------------------------------------------------------------------------------
# NCC
# ----------------------------------------------------------------------------------------------------------------------

output "network_connectivity_config_id" {
  description = "ID of the Network Connectivity Configuration."
  value       = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
}

output "binding_id" {
  description = "ID of the binding between the NCC and the workspace."
  value       = databricks_mws_ncc_binding.workspace.id
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoint rules
# ----------------------------------------------------------------------------------------------------------------------

# endpoint_name is the name of the private endpoint Databricks creates, which is what to match when approving connections on the target resources.
output "private_endpoint_rules" {
  description = "Rule ID, private endpoint name and connection state of every private endpoint rule, keyed by rule name."
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
