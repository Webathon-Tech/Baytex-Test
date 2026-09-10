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

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.names.log_analytics
  location            = azurerm_resource_group.ops.location
  resource_group_name = azurerm_resource_group.ops.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

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

module "network" {
  source = "../../modules/spoke-network"

  location                         = var.location
  resource_group_name              = azurerm_resource_group.network.name
  name_prefix                      = local.resource_name_prefix
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
  cisco_firewall_private_ip        = var.cisco_firewall_private_ip
  on_prem_routes                   = var.on_prem_routes
  hub_vnet_id                      = var.hub_vnet_id
  create_spoke_to_hub_peering      = var.create_spoke_to_hub_peering
  admin_ssh_source_cidrs           = var.admin_ssh_source_cidrs
  proxy_listener_ports             = local.listener_ports
  tags                             = local.tags
}

module "data_foundation" {
  source = "../../modules/data-foundation"

  location                   = var.location
  resource_group_name        = azurerm_resource_group.data.name
  storage_account_name       = var.data_storage_account_name
  access_connector_name      = local.names.access_connector
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  containers                 = var.data_containers
  blob_private_dns_zone_ids  = var.blob_private_dns_zone_ids
  dfs_private_dns_zone_ids   = var.dfs_private_dns_zone_ids
  tags                       = local.tags
}

module "haproxy" {
  source = "../../modules/haproxy-tier"

  location                           = var.location
  resource_group_name                = azurerm_resource_group.connectivity.name
  name_prefix                        = local.resource_name_prefix
  proxy_subnet_id                    = module.network.proxy_subnet_id
  proxy_vm_size                      = var.proxy_vm_size
  proxy_vm_private_ips               = var.proxy_vm_private_ips
  admin_username                     = "azureadmin"
  ssh_public_key                     = var.ssh_public_key
  dns_servers                        = var.dns_servers
  endpoints                          = var.on_prem_endpoints
  allow_all_subscriptions_visibility = var.allow_all_subscriptions_pls_visibility
  visibility_subscription_ids        = var.pls_visibility_subscription_ids
  auto_approval_subscription_ids     = var.pls_auto_approval_subscription_ids
  tags                               = local.tags
}

module "databricks_workspace" {
  source  = "Azure/avm-res-databricks-workspace/azurerm"
  version = "0.5.0"

  # No depends_on here, deliberately. resource_group_name below references azurerm_resource_group.platform, which is a
  # real dependency edge, so Terraform still orders the module after the group and still defers the module's resource
  # group data read on a first run. A module-level depends_on would additionally mark every data source inside the
  # module unknown at plan time on EVERY run, and that unknown propagates into the workspace's parent_id -- which makes
  # Terraform report a full workspace replacement for something as small as a tag edit.

  name                              = local.names.workspace
  resource_group_name               = azurerm_resource_group.platform.name
  location                          = var.location
  sku                               = "premium"
  compute_mode                      = "Hybrid"
  managed_resource_group_name       = local.names.managed_resource_group
  public_network_access_enabled     = var.workspace_public_network_access_enabled
  default_storage_firewall_enabled  = var.workspace_default_storage_firewall_enabled
  access_connector_id               = var.workspace_default_storage_firewall_enabled ? module.data_foundation.access_connector_id : null
  infrastructure_encryption_enabled = var.workspace_infrastructure_encryption_enabled
  enable_telemetry                  = false
  tags                              = local.tags

  default_catalog = {
    initial_type = "UnityCatalog"
    initial_name = var.default_catalog_initial_name
  }

  custom_parameters = {
    no_public_ip                                         = true
    virtual_network_id                                   = module.network.vnet_id
    public_subnet_name                                   = module.network.databricks_host_subnet_name
    private_subnet_name                                  = module.network.databricks_container_subnet_name
    public_subnet_network_security_group_association_id  = module.network.host_nsg_association_id
    private_subnet_network_security_group_association_id = module.network.container_nsg_association_id
    storage_account_name                                 = var.workspace_root_storage_account_name
    storage_account_sku_name                             = "Standard_GRS"
  }

  diagnostic_settings = var.enable_diagnostics ? {
    primary = {
      name                  = local.names.diagnostic_setting
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}
}

module "ncc" {
  source = "../../modules/ncc"

  providers = {
    databricks = databricks.account
  }

  name                  = local.names.ncc
  region                = var.location
  workspace_id          = module.databricks_workspace.databricks_workspace_id
  storage_account_id    = module.data_foundation.storage_account_id
  private_link_services = local.private_link_services_for_ncc
}

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
}

resource "azurerm_monitor_diagnostic_setting" "data_storage_blob" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-data-storage-blob"
  target_resource_id         = module.data_foundation.blob_service_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # log_analytics_destination_type is deliberately NOT set. Storage blob logs
  # (StorageRead/StorageWrite/StorageDelete) always land in the resource-specific
  # StorageBlobLogs table, so Azure silently discards the value and returns null.
  # Setting it produced a perpetual "will be updated in-place" diff on every plan,
  # which would break the "plan contains only expected changes" acceptance gate.

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
}

resource "azurerm_monitor_diagnostic_setting" "load_balancer" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-load-balancer"
  target_resource_id         = module.haproxy.load_balancer_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nat_gateway" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${local.resource_name_prefix}-nat"
  target_resource_id         = module.network.nat_gateway_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}
