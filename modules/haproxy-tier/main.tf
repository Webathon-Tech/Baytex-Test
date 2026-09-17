# ----------------------------------------------------------------------------------------------------------------------
# HAProxy tier module
# Two HAProxy VMs, in availability zones 1 and 2, behind an internal Standard Load Balancer, with one frontend and one Private Link Service per on-premises destination.
# Databricks serverless compute reaches each destination through its Private Link Service, and HAProxy forwards the connection to the on-premises host.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # One VM per availability zone, each with a static private IP: the first address is placed in zone 1 and the second in zone 2.
  proxy_nodes = {
    for index, private_ip in var.proxy_vm_private_ips : format("%02d", index + 1) => {
      private_ip = private_ip
      zone       = tostring(index + 1)
    }
  }

  # VM sizes from the v6 generation onwards support only NVMe disk controllers.
  # Earlier sizes keep Azure's default SCSI controller.
  disk_controller_type = can(regex("_v[6-9]$", var.proxy_vm_size)) ? "NVMe" : null

  # Line endings are normalised to LF so every file works on Linux regardless of the operating system that runs Terraform.
  haproxy_config = replace(templatefile("${path.module}/templates/haproxy.cfg.tftpl", {
    dns_servers = var.dns_servers
    endpoints   = var.endpoints
  }), "\r\n", "\n")

  configure_script = replace(templatefile("${path.module}/templates/configure-haproxy.sh.tftpl", {
    haproxy_cfg_base64 = base64encode(local.haproxy_config)
    frontend_ips       = sort([for endpoint in values(var.endpoints) : endpoint.frontend_ip])
  }), "\r\n", "\n")

  # Weekly patch windows, one per availability zone, so the two HAProxy VMs are never patched or restarted at the same time.
  patch_windows = {
    "1" = "Saturday"
    "2" = "Sunday"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# HAProxy virtual machines
# ----------------------------------------------------------------------------------------------------------------------

# Accelerated networking is enabled and each NIC has a static private IP from proxy_vm_private_ips.
resource "azurerm_network_interface" "proxy" {
  for_each = local.proxy_nodes

  name                           = "nic-${var.name_prefix}-proxy-${each.key}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.proxy_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

# Ubuntu LTS on Trusted Launch (secure boot and vTPM), with SSH key authentication only.
# cloud-init installs HAProxy when the VM is created, and the haproxy_config extension below applies its configuration.
# The custom data has no inputs, so it is the same on every apply; changing templates/cloud-init.yaml replaces the VMs, because custom data can be set only when a VM is created.
#
# Patches are installed by Azure Update Manager in the zone's weekly window below, rather than at times the platform chooses.
resource "azurerm_linux_virtual_machine" "proxy" {
  for_each = local.proxy_nodes

  name                            = "vm-${var.name_prefix}-proxy-${each.key}"
  computer_name                   = "${var.name_prefix}-proxy-${each.key}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.proxy_vm_size
  disk_controller_type            = local.disk_controller_type
  zone                            = each.value.zone
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.proxy[each.key].id]
  custom_data                     = base64encode(replace(file("${path.module}/templates/cloud-init.yaml"), "\r\n", "\n"))
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  provision_vm_agent              = true

  # MaintenanceSchedule names the patch schedule for the VM's zone, and is the tag that schedule's dynamic scope matches.
  tags = merge(var.tags, { MaintenanceSchedule = "mc-${var.name_prefix}-proxy-zone${each.value.zone}" })

  # The bypass setting hands patch timing to the Update Manager schedule, as customer-managed schedules require.
  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  reboot_setting                                         = "IfRequired"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.name_prefix}-proxy-${each.key}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-26_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Boot diagnostics use a Microsoft-managed storage account.
  boot_diagnostics {}

  # Creating the VM and adding its NIC to the backend pool both update the NIC, and neither resource locks the other.
  depends_on = [azurerm_network_interface_backend_address_pool_association.proxy]
}

# ----------------------------------------------------------------------------------------------------------------------
# HAProxy configuration
# ----------------------------------------------------------------------------------------------------------------------

# Applies the HAProxy configuration and the load balancer frontend IPs with the Custom Script Extension, from templates/configure-haproxy.sh.tftpl.
# The extension runs when the VM is created and again whenever the destinations or DNS servers change, without replacing the VM.
# HAProxy validates the new configuration before it is used, and a failed run fails the apply while HAProxy keeps its current configuration.
# The settings are protected because they carry the whole script; terraform_data.haproxy_config shows the configuration itself in the plan.
resource "azurerm_virtual_machine_extension" "haproxy_config" {
  for_each = azurerm_linux_virtual_machine.proxy

  name                       = "configure-haproxy"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  protected_settings = jsonencode({
    script = base64gzip(local.configure_script)
  })
}

# Shows the rendered HAProxy configuration as a readable diff in the plan.
resource "terraform_data" "haproxy_config" {
  input = local.haproxy_config
}

# ----------------------------------------------------------------------------------------------------------------------
# Patching
# ----------------------------------------------------------------------------------------------------------------------

# One Azure Update Manager schedule per availability zone: two hours from 02:00 Mountain Time, Saturday for zone 1 and Sunday for zone 2, installing critical and security updates and restarting only when an update requires it.
# The maintenance configuration API accepts only lowercase tag keys, so the platform tags are not applied here.
resource "azurerm_maintenance_configuration" "patching" {
  for_each = local.patch_windows

  name                     = "mc-${var.name_prefix}-proxy-zone${each.key}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"

  window {
    start_date_time = "2026-09-19 02:00"
    duration        = "02:00"
    time_zone       = "Mountain Standard Time"
    recur_every     = "1Week ${each.value}"
  }

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include = ["Critical", "Security"]
    }
  }
}

# Each schedule applies to the Linux VMs in this resource group that carry its MaintenanceSchedule tag.
# A dynamic scope is not tied to a VM resource, so a replaced VM is covered by its schedule as soon as it exists.
resource "azurerm_maintenance_assignment_dynamic_scope" "patching" {
  for_each = azurerm_maintenance_configuration.patching

  name                         = "${var.name_prefix}-proxy-zone${each.key}"
  maintenance_configuration_id = each.value.id

  filter {
    locations       = [var.location]
    os_types        = ["Linux"]
    resource_groups = [var.resource_group_name]
    resource_types  = ["Microsoft.Compute/virtualMachines"]
    tag_filter      = "All"

    tags {
      tag    = "MaintenanceSchedule"
      values = [each.value.name]
    }
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Internal load balancer
# ----------------------------------------------------------------------------------------------------------------------

# One static frontend IP per on-premises destination.
resource "azurerm_lb" "this" {
  name                = "lb-${var.name_prefix}-proxy"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  dynamic "frontend_ip_configuration" {
    for_each = var.endpoints
    content {
      name                          = "fe-${frontend_ip_configuration.key}"
      subnet_id                     = var.proxy_subnet_id
      private_ip_address            = frontend_ip_configuration.value.frontend_ip
      private_ip_address_allocation = "Static"
    }
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = "be-${var.name_prefix}-proxy"
  loadbalancer_id = azurerm_lb.this.id
}

resource "azurerm_network_interface_backend_address_pool_association" "proxy" {
  for_each = azurerm_network_interface.proxy

  network_interface_id    = each.value.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id

  # Adding a NIC to the pool updates the load balancer, but this resource locks only the NIC, so it waits until the probe is written.
  depends_on = [azurerm_lb_probe.haproxy]
}

# Requests the HAProxy health frontend over HTTP, so a VM stays in the pool only while HAProxy itself answers requests, not
# merely while something accepts connections on the port. A VM leaves the pool after one failed probe.
resource "azurerm_lb_probe" "haproxy" {
  name                = "probe-haproxy-8404"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Http"
  port                = 8404
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
  probe_threshold     = 1
}

# Floating IP keeps the frontend IP as the destination address, so each HAProxy frontend binds to its own frontend IP and port.
# Outbound SNAT is disabled because the load balancer carries no outbound traffic.
# TCP reset is sent to both ends of a connection that reaches the idle timeout, so clients reconnect straight away instead
# of waiting on a connection that was dropped silently.
resource "azurerm_lb_rule" "endpoint" {
  for_each = var.endpoints

  name                           = "rule-${each.key}"
  loadbalancer_id                = azurerm_lb.this.id
  frontend_ip_configuration_name = "fe-${each.key}"
  protocol                       = "Tcp"
  frontend_port                  = each.value.listen_port
  backend_port                   = each.value.listen_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.haproxy.id
  floating_ip_enabled            = true
  disable_outbound_snat          = true
  idle_timeout_in_minutes        = 30
  tcp_reset_enabled              = true
  load_distribution              = "Default"

  # The NIC backend pool associations and the VMs also write to the load balancer, under a different provider lock than
  # the rules. Run in parallel, Azure rejects a rule with ConflictingConcurrentWriteNotAllowed.
  depends_on = [
    azurerm_network_interface_backend_address_pool_association.proxy,
    azurerm_linux_virtual_machine.proxy,
  ]
}

# ----------------------------------------------------------------------------------------------------------------------
# Private Link Services
# ----------------------------------------------------------------------------------------------------------------------

# One Private Link Service per destination, on that destination's load balancer frontend.
# The Databricks NCC creates a private endpoint to each one, and the connection must be approved unless its subscription is in auto_approval_subscription_ids.
resource "azurerm_private_link_service" "endpoint" {
  for_each = var.endpoints

  name                = "pls-${var.name_prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  # The frontend's resource ID is composed from the load balancer ID rather than read back from its frontend_ip_configuration attribute.
  # Azure reports that attribute as computed, so while a destination is being added or renamed it still holds the previous set and no frontend would match the new name.
  load_balancer_frontend_ip_configuration_ids = [
    "${azurerm_lb.this.id}/frontendIPConfigurations/fe-${each.key}"
  ]
  visibility_subscription_ids    = var.allow_all_subscriptions_visibility ? [] : var.visibility_subscription_ids
  auto_approval_subscription_ids = var.auto_approval_subscription_ids
  fqdns                          = [each.value.domain_name]
  tags                           = var.tags

  nat_ip_configuration {
    name                       = "nat-${each.key}"
    private_ip_address         = each.value.pls_nat_ip
    private_ip_address_version = "IPv4"
    subnet_id                  = var.proxy_subnet_id
    primary                    = true
  }

  lifecycle {
    # Visibility must be restricted to named subscriptions unless all-subscription visibility is explicitly enabled.
    precondition {
      condition     = var.allow_all_subscriptions_visibility || length(var.visibility_subscription_ids) > 0
      error_message = "Provide explicit visibility_subscription_ids or set allow_all_subscriptions_visibility=true as an approved exception."
    }

    # Azure accepts auto-approval only for subscriptions that are also in the visibility list.
    precondition {
      condition = var.allow_all_subscriptions_visibility || length(setsubtract(
        toset(var.auto_approval_subscription_ids),
        toset(var.visibility_subscription_ids)
      )) == 0
      error_message = "Private Link Service auto-approval subscriptions must be included in the visibility list."
    }
  }

  depends_on = [azurerm_lb_rule.endpoint]
}

# ----------------------------------------------------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------------------------------------------------

# Every alert below exists only when enable_alerts is true, notifies the action groups in alert_action_group_ids, and
# resolves automatically once its condition clears.

# Raised while fewer than all HAProxy VMs answer the health probe, for example while a VM restarts or installs HAProxy.
# The remaining VMs keep serving every destination.
resource "azurerm_monitor_metric_alert" "health_probe_degraded" {
  count = var.enable_alerts ? 1 : 0

  name                = "alert-${var.name_prefix}-proxy-health-probe-degraded"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_lb.this.id]
  description         = "Fewer than all HAProxy VMs behind lb-${var.name_prefix}-proxy answer the health probe. The remaining VMs keep serving."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }

  depends_on = [azurerm_lb_probe.haproxy]
}

# Raised when practically no HAProxy VM has answered the health probe for five minutes, which leaves serverless compute
# without a path to any on-premises destination. Health Probe Status supports only the Average aggregation, so an average
# below 10 percent across all VMs stands for every VM failing nearly every probe.
resource "azurerm_monitor_metric_alert" "health_probe_down" {
  count = var.enable_alerts ? 1 : 0

  name                = "alert-${var.name_prefix}-proxy-health-probe-down"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_lb.this.id]
  description         = "No HAProxy VM behind lb-${var.name_prefix}-proxy answers the health probe. Serverless compute cannot reach any on-premises destination."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 10
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }

  depends_on = [azurerm_lb_probe.haproxy]
}

# Raised when Azure Resource Health reports an HAProxy VM unavailable or degraded because of a platform event, such as a
# host failure. Restarts and other changes made by an operator do not raise it.
resource "azurerm_monitor_activity_log_alert" "proxy_vm_resource_health" {
  count = var.enable_alerts ? 1 : 0

  name                = "alert-${var.name_prefix}-proxy-vm-resource-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [for vm in azurerm_linux_virtual_machine.proxy : vm.id]
  description         = "An HAProxy VM is unavailable or degraded because of an Azure platform event."
  tags                = var.tags

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Degraded", "Unavailable"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# Raised when an HAProxy VM stays busy or short of memory for 15 minutes, a sign that the tier needs a larger VM size.
# Both alerts evaluate every VM separately.
resource "azurerm_monitor_metric_alert" "proxy_vm_cpu" {
  count = var.enable_alerts ? 1 : 0

  name                     = "alert-${var.name_prefix}-proxy-vm-cpu"
  resource_group_name      = var.resource_group_name
  scopes                   = [for vm in azurerm_linux_virtual_machine.proxy : vm.id]
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = var.location
  description              = "An HAProxy VM has averaged more than 85 percent CPU for 15 minutes."
  severity                 = 3
  frequency                = "PT5M"
  window_size              = "PT15M"
  tags                     = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "proxy_vm_memory" {
  count = var.enable_alerts ? 1 : 0

  name                     = "alert-${var.name_prefix}-proxy-vm-memory"
  resource_group_name      = var.resource_group_name
  scopes                   = [for vm in azurerm_linux_virtual_machine.proxy : vm.id]
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = var.location
  description              = "An HAProxy VM has averaged less than 10 percent available memory for 15 minutes."
  severity                 = 3
  frequency                = "PT5M"
  window_size              = "PT15M"
  tags                     = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Percentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 10
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
