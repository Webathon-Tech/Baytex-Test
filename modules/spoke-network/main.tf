locals {
  sorted_listener_ports = sort([for port in var.proxy_listener_ports : tostring(port)])
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_network_security_group" "databricks_host" {
  name                = "nsg-${var.name_prefix}-dbx-host"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "databricks_container" {
  name                = "nsg-${var.name_prefix}-dbx-container"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "proxy" {
  name                = "nsg-${var.name_prefix}-proxy"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "proxy_health_probe" {
  name                        = "Allow-AzureLoadBalancer-HealthProbe"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8404"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.proxy.name
}

resource "azurerm_network_security_rule" "proxy_listener" {
  for_each = toset(local.sorted_listener_ports)

  name                        = "Allow-PrivateLink-TCP-${each.value}"
  priority                    = 200 + index(local.sorted_listener_ports, each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = var.proxy_subnet_cidr
  destination_address_prefix  = var.proxy_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.proxy.name
}

resource "azurerm_network_security_rule" "proxy_ssh" {
  for_each = { for index, cidr in var.admin_ssh_source_cidrs : format("%02d", index + 1) => cidr }

  name                        = "Allow-SSH-${each.key}"
  priority                    = 400 + tonumber(each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.proxy.name
}

resource "azurerm_subnet" "databricks_host" {
  name                            = var.databricks_host_subnet_name
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.databricks_host_subnet_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "databricks"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet" "databricks_container" {
  name                            = var.databricks_container_subnet_name
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.databricks_container_subnet_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "databricks"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = var.private_endpoint_subnet_name
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "proxy" {
  name                                          = var.proxy_subnet_name
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [var.proxy_subnet_cidr]
  default_outbound_access_enabled               = false
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "databricks_host" {
  subnet_id                 = azurerm_subnet.databricks_host.id
  network_security_group_id = azurerm_network_security_group.databricks_host.id
}

resource "azurerm_subnet_network_security_group_association" "databricks_container" {
  subnet_id                 = azurerm_subnet.databricks_container.id
  network_security_group_id = azurerm_network_security_group.databricks_container.id
}

resource "azurerm_subnet_network_security_group_association" "proxy" {
  subnet_id                 = azurerm_subnet.proxy.id
  network_security_group_id = azurerm_network_security_group.proxy.id
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.name_prefix}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "nat-${var.name_prefix}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 20
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "databricks_host" {
  subnet_id      = azurerm_subnet.databricks_host.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet_nat_gateway_association" "databricks_container" {
  subnet_id      = azurerm_subnet.databricks_container.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet_nat_gateway_association" "proxy" {
  subnet_id      = azurerm_subnet.proxy.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_route_table" "this" {
  name                          = "rt-${var.name_prefix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route" "on_prem" {
  for_each = var.on_prem_routes

  name                   = "route-${each.key}"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = each.value.address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.cisco_firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "databricks_host" {
  subnet_id      = azurerm_subnet.databricks_host.id
  route_table_id = azurerm_route_table.this.id
}

resource "azurerm_subnet_route_table_association" "databricks_container" {
  subnet_id      = azurerm_subnet.databricks_container.id
  route_table_id = azurerm_route_table.this.id
}

resource "azurerm_subnet_route_table_association" "proxy" {
  subnet_id      = azurerm_subnet.proxy.id
  route_table_id = azurerm_route_table.this.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.create_spoke_to_hub_peering ? 1 : 0

  name                         = "peer-${var.name_prefix}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
