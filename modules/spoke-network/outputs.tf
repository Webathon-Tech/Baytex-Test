# ----------------------------------------------------------------------------------------------------------------------
# Virtual network and subnets
# ----------------------------------------------------------------------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the spoke VNet."
  value       = azurerm_virtual_network.this.name
}

output "databricks_host_subnet_id" {
  description = "Resource ID of the Databricks host (public) subnet."
  value       = azurerm_subnet.databricks_host.id
}

output "databricks_host_subnet_name" {
  description = "Name of the Databricks host (public) subnet."
  value       = azurerm_subnet.databricks_host.name
}

output "databricks_container_subnet_id" {
  description = "Resource ID of the Databricks container (private) subnet."
  value       = azurerm_subnet.databricks_container.id
}

output "databricks_container_subnet_name" {
  description = "Name of the Databricks container (private) subnet."
  value       = azurerm_subnet.databricks_container.name
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "proxy_subnet_id" {
  description = "Resource ID of the proxy subnet."
  value       = azurerm_subnet.proxy.id
}

# ----------------------------------------------------------------------------------------------------------------------
# Network security, egress and routing
# ----------------------------------------------------------------------------------------------------------------------

output "host_nsg_association_id" {
  description = "ID of the NSG association on the Databricks host subnet, required by the workspace."
  value       = azurerm_subnet_network_security_group_association.databricks_host.id
}

output "container_nsg_association_id" {
  description = "ID of the NSG association on the Databricks container subnet, required by the workspace."
  value       = azurerm_subnet_network_security_group_association.databricks_container.id
}

output "nat_gateway_id" {
  description = "Resource ID of the NAT Gateway."
  value       = azurerm_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Public IP address the Databricks subnets use for internet egress."
  value       = azurerm_public_ip.nat.ip_address
}

output "databricks_route_table_id" {
  description = "Resource ID of the route table on the Databricks subnets."
  value       = azurerm_route_table.databricks.id
}

output "default_route_table_id" {
  description = "Resource ID of the route table on the proxy and private endpoint subnets."
  value       = azurerm_route_table.default.id
}

# ----------------------------------------------------------------------------------------------------------------------
# VNet peering
# ----------------------------------------------------------------------------------------------------------------------

output "spoke_to_hub_peering_id" {
  description = "Resource ID of the spoke-side peering, or null when create_spoke_to_hub_peering is false."
  value       = one(azurerm_virtual_network_peering.spoke_to_hub[*].id)
}

output "hub_to_spoke_peering_id" {
  description = "Resource ID of the hub-side peering, or null when create_hub_to_spoke_peering is false."
  value       = one(azapi_resource.hub_to_spoke_peering[*].id)
}
