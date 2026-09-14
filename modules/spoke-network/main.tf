# ----------------------------------------------------------------------------------------------------------------------
# Spoke network module
# Builds the environment's spoke VNet: subnets, network security groups, NAT Gateway, route tables and the optional VNet peering with the hub in both directions.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # Listener ports are sorted so every proxy NSG rule keeps the same priority from one plan to the next.
  sorted_listener_ports = sort([for port in var.proxy_listener_ports : tostring(port)])
}

# ----------------------------------------------------------------------------------------------------------------------
# Virtual network
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_servers         = var.dns_servers
  tags                = var.tags
}

# ----------------------------------------------------------------------------------------------------------------------
# Network security groups
# ----------------------------------------------------------------------------------------------------------------------

# The Databricks host and container NSGs are created empty.
# Databricks adds and maintains the rules it needs once the workspace is attached to these subnets.
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

# The proxy NSG explicitly allows the load balancer health probe, Private Link Service traffic on each listener port and, optionally, administrative SSH.
resource "azurerm_network_security_group" "proxy" {
  name                = "nsg-${var.name_prefix}-proxy"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "proxy_health_probe" {
  name                        = "Allow-AzureLoadBalancer-HealthProbe"
  description                 = "Allows the Azure Load Balancer health probe to reach HAProxy on TCP 8404."
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

# Private Link Service traffic reaches the load balancer frontends from the Private Link Service NAT IPs, and both sit inside the proxy subnet.
resource "azurerm_network_security_rule" "proxy_listener" {
  for_each = toset(local.sorted_listener_ports)

  name                        = "Allow-PrivateLink-TCP-${each.value}"
  description                 = "Allows Private Link Service traffic to the HAProxy listeners on TCP ${each.value}."
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

# One rule per entry in admin_ssh_source_cidrs; an empty list creates no SSH rule.
resource "azurerm_network_security_rule" "proxy_ssh" {
  for_each = { for index, cidr in var.admin_ssh_source_cidrs : format("%02d", index + 1) => cidr }

  name                        = "Allow-SSH-${each.key}"
  description                 = "Allows administrative SSH to the HAProxy VMs from ${each.value}."
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

# ----------------------------------------------------------------------------------------------------------------------
# Subnets
# ----------------------------------------------------------------------------------------------------------------------

# Every subnet sets default_outbound_access_enabled = false, so traffic leaves only through the NAT Gateway or the firewall route and never through Azure's implicit outbound access.

# The host and container subnets are delegated to Azure Databricks for VNet injection.
# In Databricks terms the host subnet is the "public" subnet and the container subnet is the "private" subnet, although neither has public IPs.
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

# Holds the blob and dfs private endpoints of the data storage account.
# With private endpoint network policies disabled, NSGs and route tables are not applied to the private endpoints themselves.
resource "azurerm_subnet" "private_endpoints" {
  name                              = var.private_endpoint_subnet_name
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

# Holds the HAProxy VMs, the internal load balancer frontends and the Private Link Service NAT IPs.
# Azure requires Private Link Service network policies to be disabled on the subnet that holds the NAT IPs.
resource "azurerm_subnet" "proxy" {
  name                                          = var.proxy_subnet_name
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [var.proxy_subnet_cidr]
  default_outbound_access_enabled               = false
  private_link_service_network_policies_enabled = false
}

# ----------------------------------------------------------------------------------------------------------------------
# NSG associations
# ----------------------------------------------------------------------------------------------------------------------

# The workspace module receives the host and container association IDs, so the workspace is created only after both NSGs are attached.
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

# ----------------------------------------------------------------------------------------------------------------------
# NAT Gateway
# ----------------------------------------------------------------------------------------------------------------------

# Internet egress for the Databricks host and container subnets, through one static public IP.
# The proxy and private endpoint subnets are not associated, because they send all traffic to the firewall.
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

# ----------------------------------------------------------------------------------------------------------------------
# Route tables
# ----------------------------------------------------------------------------------------------------------------------

# Two route tables separate the Databricks subnets from the rest of the spoke.
# The databricks route table sends only the prefixes in on_prem_routes to the firewall, and everything else leaves through the NAT Gateway.
# Routing all Databricks traffic through the firewall would require every Databricks control-plane and artifact endpoint to be allowed on it.
# The default route table sends all traffic, 0.0.0.0/0, to the firewall.
# A 0.0.0.0/0 route to a virtual appliance takes precedence over a NAT Gateway, which is why the proxy subnet has none.
resource "azurerm_route_table" "databricks" {
  name                          = "rt-${var.name_prefix}-databricks"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route" "on_prem" {
  for_each = var.on_prem_routes

  name                   = "route-${each.key}"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.databricks.name
  address_prefix         = each.value.address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.cisco_firewall_private_ip
}

resource "azurerm_route_table" "default" {
  name                          = "rt-${var.name_prefix}-default"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  name                   = "route-default-to-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.default.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.cisco_firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "databricks_host" {
  subnet_id      = azurerm_subnet.databricks_host.id
  route_table_id = azurerm_route_table.databricks.id
}

resource "azurerm_subnet_route_table_association" "databricks_container" {
  subnet_id      = azurerm_subnet.databricks_container.id
  route_table_id = azurerm_route_table.databricks.id
}

resource "azurerm_subnet_route_table_association" "proxy" {
  subnet_id      = azurerm_subnet.proxy.id
  route_table_id = azurerm_route_table.default.id
}

resource "azurerm_subnet_route_table_association" "private_endpoints" {
  subnet_id      = azurerm_subnet.private_endpoints.id
  route_table_id = azurerm_route_table.default.id
}

# ----------------------------------------------------------------------------------------------------------------------
# VNet peering
# ----------------------------------------------------------------------------------------------------------------------

# Each direction is created only when its flag is true, and the two can be enabled independently.
# Gateway transit is not used, because the route tables above send on-premises traffic to the firewall.

# Spoke side: a peering on the spoke VNet, created in this environment's subscription.
# When the hub VNet is in another subscription, the deployment identity also needs Microsoft.Network/virtualNetworks/peer/action on the hub VNet, which Network Contributor on the hub VNet grants.
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

# Hub side: a peering on the hub VNet, created through the Azure Resource Manager API as a child of hub_vnet_id.
# Addressing the hub VNet by its full resource ID means no provider has to be configured for the hub subscription.
# The deployment identity needs only Network Contributor on the hub VNet, not access to the hub subscription itself.
resource "azapi_resource" "hub_to_spoke_peering" {
  count = var.create_hub_to_spoke_peering ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01"
  name      = "peer-hub-to-${var.name_prefix}"
  parent_id = var.hub_vnet_id

  body = {
    properties = {
      remoteVirtualNetwork = {
        id = azurerm_virtual_network.this.id
      }
      allowVirtualNetworkAccess = true
      allowForwardedTraffic     = true
      allowGatewayTransit       = false
      useRemoteGateways         = false
    }
  }

  # azapi takes no provider locks, so the hub side waits until every subnet change on the spoke VNet it peers with has finished.
  depends_on = [
    azurerm_subnet_network_security_group_association.databricks_host,
    azurerm_subnet_network_security_group_association.databricks_container,
    azurerm_subnet_network_security_group_association.proxy,
    azurerm_subnet_nat_gateway_association.databricks_host,
    azurerm_subnet_nat_gateway_association.databricks_container,
    azurerm_subnet_route_table_association.databricks_host,
    azurerm_subnet_route_table_association.databricks_container,
    azurerm_subnet_route_table_association.proxy,
    azurerm_subnet_route_table_association.private_endpoints,
  ]
}
