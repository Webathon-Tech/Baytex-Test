# ----------------------------------------------------------------------------------------------------------------------
# Platform root
# Builds one environment of the Baytex Azure Databricks platform from the modules in ../../modules.
# The dev, test and prod roots hold identical .tf files, and each environment's values come from its terraform.tfvars.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Resource groups
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "network" {
  name     = local.names.rg_network
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "platform" {
  name     = local.names.rg_platform
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "data" {
  name     = local.names.rg_data
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "connectivity" {
  name     = local.names.rg_connectivity
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "ops" {
  name     = local.names.rg_ops
  location = var.location
  tags     = local.tags
}

# ----------------------------------------------------------------------------------------------------------------------
# Spoke network
# VNet, subnets, NSGs, NAT Gateway, route tables and the optional VNet peering with the hub.
# ----------------------------------------------------------------------------------------------------------------------

module "network" {
  source = "../../modules/spoke-network"

  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  name_prefix         = local.resource_name_prefix
  tags                = local.tags

  vnet_name                        = local.names.vnet
  vnet_cidr                        = var.vnet_cidr
  dns_servers                      = var.dns_servers
  databricks_host_subnet_name      = local.names.databricks_host_subnet
  databricks_host_subnet_cidr      = var.databricks_host_subnet_cidr
  databricks_container_subnet_name = local.names.databricks_container_subnet
  databricks_container_subnet_cidr = var.databricks_container_subnet_cidr
  private_endpoint_subnet_name     = local.names.private_endpoint_subnet
  private_endpoint_subnet_cidr     = var.private_endpoint_subnet_cidr
  proxy_subnet_name                = local.names.proxy_subnet
  proxy_subnet_cidr                = var.proxy_subnet_cidr

  hub_vnet_id                 = var.hub_vnet_id
  create_spoke_to_hub_peering = var.create_spoke_to_hub_peering
  create_hub_to_spoke_peering = var.create_hub_to_spoke_peering
  cisco_firewall_private_ip   = var.cisco_firewall_private_ip
  firewall_routes             = var.firewall_routes

  databricks_nsg_rules = var.databricks_nsg_rules
  proxy_nsg_rules      = var.proxy_nsg_rules

  admin_ssh_source_cidrs = var.admin_ssh_source_cidrs
  proxy_listener_ports   = local.listener_ports
}

# ----------------------------------------------------------------------------------------------------------------------
# Data foundation
# ADLS Gen2 data storage account, containers, data Access Connector and storage private endpoints.
# ----------------------------------------------------------------------------------------------------------------------

module "data_foundation" {
  source = "../../modules/data-foundation"

  location            = var.location
  resource_group_name = azurerm_resource_group.data.name
  tags                = local.tags

  storage_account_name  = var.data_storage_account_name
  containers            = var.data_containers
  access_connector_name = local.names.access_connector_data

  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  blob_private_dns_zone_ids  = var.blob_private_dns_zone_ids
  dfs_private_dns_zone_ids   = var.dfs_private_dns_zone_ids
  blob_private_endpoint_ip   = var.blob_private_endpoint_ip
  dfs_private_endpoint_ip    = var.dfs_private_endpoint_ip
}

# ----------------------------------------------------------------------------------------------------------------------
# HAProxy tier and Private Link Services
# Private connectivity from Databricks serverless compute to the on-premises destinations.
# ----------------------------------------------------------------------------------------------------------------------

module "haproxy" {
  source = "../../modules/haproxy-tier"

  location            = var.location
  resource_group_name = azurerm_resource_group.connectivity.name
  name_prefix         = local.resource_name_prefix
  tags                = local.tags

  proxy_subnet_id      = module.network.proxy_subnet_id
  proxy_vm_size        = var.proxy_vm_size
  proxy_vm_private_ips = var.proxy_vm_private_ips
  admin_username       = "azureadmin"
  ssh_public_key       = var.ssh_public_key
  dns_servers          = var.dns_servers

  endpoints = var.on_prem_endpoints

  allow_all_subscriptions_visibility = var.allow_all_subscriptions_pls_visibility
  visibility_subscription_ids        = var.pls_visibility_subscription_ids
  auto_approval_subscription_ids     = var.pls_auto_approval_subscription_ids
}

# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace
# Premium workspace injected into the spoke VNet, and the root Access Connector when the default storage firewall is enabled.
# ----------------------------------------------------------------------------------------------------------------------

module "databricks_workspace" {
  source = "../../modules/databricks-workspace"

  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags

  name                              = local.names.workspace
  managed_resource_group_name       = local.names.managed_resource_group
  root_storage_account_name         = var.workspace_root_storage_account_name
  public_network_access_enabled     = var.workspace_public_network_access_enabled
  infrastructure_encryption_enabled = var.workspace_infrastructure_encryption_enabled
  default_storage_firewall_enabled  = var.workspace_default_storage_firewall_enabled
  root_access_connector_name        = local.names.access_connector_root

  virtual_network_id           = module.network.vnet_id
  host_subnet_name             = module.network.databricks_host_subnet_name
  container_subnet_name        = module.network.databricks_container_subnet_name
  host_nsg_association_id      = module.network.host_nsg_association_id
  container_nsg_association_id = module.network.container_nsg_association_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Network Connectivity Configuration
# Serverless private endpoint rules to the data storage account and to every Private Link Service.
# ----------------------------------------------------------------------------------------------------------------------

module "ncc" {
  source = "../../modules/ncc"

  providers = {
    databricks = databricks.account
  }

  name                  = local.names.ncc
  region                = var.location
  workspace_id          = module.databricks_workspace.workspace_id
  storage_account_id    = module.data_foundation.storage_account_id
  private_link_services = local.private_link_services_for_ncc
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress
# The Databricks network policy that limits which internet destinations serverless compute may reach, attached to this workspace.
# ----------------------------------------------------------------------------------------------------------------------

module "serverless_egress" {
  source = "../../modules/serverless-egress"

  count = var.create_serverless_network_policy ? 1 : 0

  providers = {
    databricks = databricks.account
  }

  network_policy_id             = local.names.network_policy
  workspace_id                  = module.databricks_workspace.workspace_id
  restriction_mode              = var.serverless_egress_restriction_mode
  enforcement_mode              = var.serverless_egress_enforcement_mode
  allowed_internet_destinations = var.serverless_allowed_internet_destinations
}

# ----------------------------------------------------------------------------------------------------------------------
# Operations
# Log Analytics workspace, alert action group and platform diagnostic settings.
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.names.log_analytics
  location            = azurerm_resource_group.ops.location
  resource_group_name = azurerm_resource_group.ops.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

# Created only when at least one email receiver is configured.
resource "azurerm_monitor_action_group" "this" {
  count = length(var.alert_email_receivers) > 0 ? 1 : 0

  name                = local.names.action_group
  resource_group_name = azurerm_resource_group.ops.name
  short_name          = local.action_group_short_name
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# Every diagnostic setting below exists only when enable_diagnostics is true, and all of them send to the Log Analytics workspace above.
# Each one also waits for the modules still changing its target, because diagnostic settings take no provider lock and would otherwise be written while the target is being updated.

# Databricks workspace: all log categories.
resource "azurerm_monitor_diagnostic_setting" "workspace" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-workspace"
  target_resource_id         = module.databricks_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  depends_on = [module.ncc]
}

# Data storage account and its blob service: every log category and metric Azure reports for each, discovered at plan time.
data "azurerm_monitor_diagnostic_categories" "data_storage" {
  count       = var.enable_diagnostics ? 1 : 0
  resource_id = module.data_foundation.storage_account_id
}

data "azurerm_monitor_diagnostic_categories" "data_storage_blob" {
  count       = var.enable_diagnostics ? 1 : 0
  resource_id = module.data_foundation.blob_service_id
}

resource "azurerm_monitor_diagnostic_setting" "data_storage" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-data-storage"
  target_resource_id         = module.data_foundation.storage_account_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.data_storage[0].log_category_types)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.data_storage[0].metrics)
    content {
      category = enabled_metric.value
    }
  }

  depends_on = [module.data_foundation, module.ncc]
}

# log_analytics_destination_type is not set.
# Storage blob logs always go to the resource-specific StorageBlobLogs table, and Azure returns no value for the setting, so setting it would show as a change on every plan.
resource "azurerm_monitor_diagnostic_setting" "data_storage_blob" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-data-storage-blob"
  target_resource_id         = module.data_foundation.blob_service_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.data_storage_blob[0].log_category_types)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.data_storage_blob[0].metrics)
    content {
      category = enabled_metric.value
    }
  }

  depends_on = [module.data_foundation, module.ncc]
}

# Internal load balancer and NAT Gateway: platform metrics.
resource "azurerm_monitor_diagnostic_setting" "load_balancer" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-load-balancer"
  target_resource_id         = module.haproxy.load_balancer_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [module.haproxy]
}

resource "azurerm_monitor_diagnostic_setting" "nat_gateway" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-nat"
  target_resource_id         = module.network.nat_gateway_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [module.network]
}
