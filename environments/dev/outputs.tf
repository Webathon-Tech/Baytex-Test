# ----------------------------------------------------------------------------------------------------------------------
# Spoke network
# ----------------------------------------------------------------------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = module.network.vnet_id
}

output "vnet_cidr" {
  description = "Address space of the spoke VNet."
  value       = var.vnet_cidr
}

output "nat_public_ip" {
  description = "Public IP address the Databricks subnets use for internet egress."
  value       = module.network.nat_public_ip
}

output "spoke_to_hub_peering_id" {
  description = "Resource ID of the spoke-side peering, or null when create_spoke_to_hub_peering is false."
  value       = module.network.spoke_to_hub_peering_id
}

output "hub_to_spoke_peering_id" {
  description = "Resource ID of the hub-side peering, or null when create_hub_to_spoke_peering is false."
  value       = module.network.hub_to_spoke_peering_id
}

# Shown only when hub_vnet_id is set and Terraform does not create the hub side of the peering, for the hub owner to run.
output "hub_side_peering_command" {
  description = "Azure CLI command that creates the hub-side peering, or null when Terraform manages it or hub_vnet_id is not set."
  value       = var.hub_vnet_id == null || var.create_hub_to_spoke_peering ? null : <<-EOT
  az network vnet peering create `
    --subscription ${local.hub_vnet.subscription_id} `
    --resource-group ${local.hub_vnet.resource_group_name} `
    --vnet-name ${local.hub_vnet.name} `
    --name peer-hub-to-${local.resource_name_prefix} `
    --remote-vnet ${module.network.vnet_id} `
    --allow-vnet-access `
    --allow-forwarded-traffic
  EOT
}

output "network_security_group_names" {
  description = "Names of the network security groups on the Databricks and proxy subnets."
  value = {
    databricks_host      = module.network.databricks_host_nsg_name
    databricks_container = module.network.databricks_container_nsg_name
    proxy                = module.network.proxy_nsg_name
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace
# ----------------------------------------------------------------------------------------------------------------------

output "databricks_workspace_arm_id" {
  description = "Azure resource ID of the Databricks workspace."
  value       = module.databricks_workspace.id
}

output "databricks_workspace_id" {
  description = "Numeric Databricks workspace ID."
  value       = module.databricks_workspace.workspace_id
}

output "databricks_workspace_url" {
  description = "Workspace URL."
  value       = "https://${module.databricks_workspace.workspace_url}"
}

output "root_access_connector_id" {
  description = "Resource ID of the root Access Connector. It is attached to the workspace only while the default storage firewall is on."
  value       = module.databricks_workspace.root_access_connector_id
}

output "root_access_connector_principal_id" {
  description = "Principal ID of the root Access Connector's managed identity."
  value       = module.databricks_workspace.root_access_connector_principal_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless connectivity
# ----------------------------------------------------------------------------------------------------------------------

output "ncc_id" {
  description = "ID of the Network Connectivity Configuration."
  value       = module.ncc.network_connectivity_config_id
}

output "ncc_private_endpoint_rules" {
  description = "Rule ID, private endpoint name and connection state of every NCC private endpoint rule. Approve only connections whose private endpoint name appears here."
  value       = module.ncc.private_endpoint_rules
}

output "private_link_service_ids" {
  description = "Resource IDs of the Private Link Services, keyed by destination name."
  value       = module.haproxy.private_link_service_ids
}

# ----------------------------------------------------------------------------------------------------------------------
# Data foundation
# ----------------------------------------------------------------------------------------------------------------------

output "data_storage_account_id" {
  description = "Resource ID of the data storage account."
  value       = module.data_foundation.storage_account_id
}

output "data_storage_account_name" {
  description = "Name of the data storage account."
  value       = module.data_foundation.storage_account_name
}

output "data_access_connector_id" {
  description = "Resource ID of the data Access Connector, used for the Unity Catalog storage credential."
  value       = module.data_foundation.access_connector_id
}

output "data_access_connector_principal_id" {
  description = "Principal ID of the data Access Connector."
  value       = module.data_foundation.access_connector_principal_id
}

output "data_private_endpoint_ips" {
  description = "Private IP addresses of the blob and dfs private endpoints of the data storage account."
  value = {
    blob = module.data_foundation.blob_private_endpoint_ip
    dfs  = module.data_foundation.dfs_private_endpoint_ip
  }
}

output "container_urls" {
  description = "abfss:// URL of each data container, keyed by container name."
  value       = module.data_foundation.container_urls
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress
# ----------------------------------------------------------------------------------------------------------------------

output "serverless_network_policy_id" {
  description = "ID of the Databricks network policy attached to the workspace, or null when create_serverless_network_policy is false."
  value       = module.ncc.network_policy_id
}

output "serverless_egress_allowed_destinations" {
  description = "Domain names serverless compute may reach on the internet, or null when create_serverless_network_policy is false."
  value       = module.ncc.allowed_internet_destinations
}

# ----------------------------------------------------------------------------------------------------------------------
# Handoffs
# ----------------------------------------------------------------------------------------------------------------------

# Everything Baytex Infrastructure needs for firewall rules and return routes.
output "firewall_handoff" {
  description = "Source subnets, routes, next hop and destination matrix for the firewall and on-premises routing changes."
  value = {
    source_vnet_cidr = var.vnet_cidr
    source_subnets = {
      databricks_host      = var.databricks_host_subnet_cidr
      databricks_container = var.databricks_container_subnet_cidr
      proxy                = var.proxy_subnet_cidr
    }
    next_hop_ip     = var.cisco_firewall_private_ip
    firewall_routes = var.firewall_routes
    default_route_subnets = {
      proxy             = var.proxy_subnet_cidr
      private_endpoints = var.private_endpoint_subnet_cidr
    }
    private_endpoint_ips = {
      blob = module.data_foundation.blob_private_endpoint_ip
      dfs  = module.data_foundation.dfs_private_endpoint_ip
    }
    destination_matrix    = local.endpoint_matrix
    required_return_route = var.vnet_cidr
  }
}

# Everything Baytex BI needs to attach the workspace to Unity Catalog.
output "unity_catalog_handoff" {
  description = "Workspace, metastore, data Access Connector and storage details for the Baytex BI Unity Catalog configuration."
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
