output "dev_vnet_id" { value = module.network.vnet_id }
output "dev_vnet_cidr" { value = var.vnet_cidr }
output "nat_public_ip" { value = module.network.nat_public_ip }
output "spoke_to_hub_peering_id" { value = module.network.spoke_to_hub_peering_id }

output "databricks_workspace_arm_id" {
  value = module.databricks_workspace.id
}

output "databricks_workspace_id" {
  value = module.databricks_workspace.workspace_id
}

output "databricks_workspace_url" {
  value = "https://${module.databricks_workspace.workspace_url}"
}

output "ncc_id" {
  value = module.ncc.network_connectivity_config_id
}

output "ncc_private_endpoint_rules" {
  value = module.ncc.private_endpoint_rules
}

output "private_link_service_ids" {
  value = module.haproxy.private_link_service_ids
}

output "data_storage_account_id" {
  value = module.data_foundation.storage_account_id
}

output "data_storage_account_name" {
  value = module.data_foundation.storage_account_name
}

output "data_access_connector_id" {
  value = module.data_foundation.access_connector_id
}

output "data_access_connector_principal_id" {
  value = module.data_foundation.access_connector_principal_id
}

output "root_access_connector_id" {
  value = module.databricks_workspace.root_access_connector_id
}

output "root_access_connector_principal_id" {
  value = module.databricks_workspace.root_access_connector_principal_id
}

output "container_urls" {
  value = module.data_foundation.container_urls
}

output "hub_side_peering_command" {
  value = <<-EOT
  az network vnet peering create `
    --subscription ${var.hub_subscription_id} `
    --resource-group ${var.hub_resource_group_name} `
    --vnet-name ${var.hub_vnet_name} `
    --name peer-hub-to-${local.resource_name_prefix} `
    --remote-vnet ${module.network.vnet_id} `
    --allow-vnet-access `
    --allow-forwarded-traffic
  EOT
}

output "firewall_handoff" {
  value = {
    source_vnet_cidr = var.vnet_cidr
    source_subnets = {
      databricks_host      = var.databricks_host_subnet_cidr
      databricks_container = var.databricks_container_subnet_cidr
      proxy                = var.proxy_subnet_cidr
    }
    next_hop_ip    = var.cisco_firewall_private_ip
    on_prem_routes = var.on_prem_routes
    default_route_subnets = {
      proxy             = var.proxy_subnet_cidr
      private_endpoints = var.private_endpoint_subnet_cidr
    }
    destination_matrix    = local.endpoint_matrix
    required_return_route = var.vnet_cidr
  }
}

output "unity_catalog_handoff" {
  value = {
    databricks_account_id         = var.databricks_account_id
    existing_metastore_id         = var.existing_metastore_id
    workspace_id                  = module.databricks_workspace.workspace_id
    workspace_url                 = "https://${module.databricks_workspace.workspace_url}"
    workspace_arm_id              = module.databricks_workspace.id
    access_connector_id           = module.data_foundation.access_connector_id
    access_connector_principal_id = module.data_foundation.access_connector_principal_id
    storage_account_id            = module.data_foundation.storage_account_id
    storage_account_name          = module.data_foundation.storage_account_name
    storage_locations             = module.data_foundation.container_urls
    environment                   = var.environment
    owner                         = "Baytex BI"
    terraform_state_boundary      = "Separate from the AMTRA platform state"
  }
}
