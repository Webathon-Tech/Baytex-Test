# ----------------------------------------------------------------------------------------------------------------------
# HAProxy tier module
# Two HAProxy VMs in separate availability zones behind an internal Standard Load Balancer, with one frontend and one Private Link Service per on-premises destination.
# Databricks serverless compute reaches each destination through its Private Link Service, and HAProxy forwards the connection to the on-premises host.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # One VM per availability zone, each with a static private IP.
  proxy_nodes = {
    "01" = {
      private_ip = var.proxy_vm_private_ips[0]
      zone       = "1"
    }
    "02" = {
      private_ip = var.proxy_vm_private_ips[1]
      zone       = "2"
    }
  }

  frontend_ips = [for endpoint in values(var.endpoints) : endpoint.frontend_ip]

  # VM sizes from the v6 generation onwards support only NVMe disk controllers.
  # Earlier sizes keep Azure's default SCSI controller.
  disk_controller_type = can(regex("_v[6-9]$", var.proxy_vm_size)) ? "NVMe" : null

  # Line endings are normalised to LF so every file works on Linux regardless of the operating system that runs Terraform.
  haproxy_config = replace(templatefile("${path.module}/templates/haproxy.cfg.tftpl", {
    dns_servers = var.dns_servers
    endpoints   = var.endpoints
  }), "\r\n", "\n")

  # Desired state, published in each VM's user data and applied on the VM by baytex-haproxy-reconcile.
  # User data is updated in place, so a change to the destinations or DNS servers reaches both VMs within about two minutes
  # without replacing them.
  desired_state = jsonencode({
    haproxy_cfg  = local.haproxy_config
    frontend_ips = sort(local.frontend_ips)
  })

  # Bootstrap files that cloud-init installs from the VM custom data.
  # None of them depends on an input, so the custom data stays the same from one apply to the next. Changing one of these
  # files replaces the VMs, because custom data can be set only when a VM is created.
  bootstrap_files = {
    reconcile_script     = replace(file("${path.module}/files/baytex-haproxy-reconcile.sh"), "\r\n", "\n")
    reconcile_service    = replace(file("${path.module}/files/baytex-haproxy-reconcile.service"), "\r\n", "\n")
    reconcile_timer      = replace(file("${path.module}/files/baytex-haproxy-reconcile.timer"), "\r\n", "\n")
    frontend_ips_service = replace(file("${path.module}/files/baytex-haproxy-frontend-ips.service"), "\r\n", "\n")
    apt_network_config   = replace(file("${path.module}/files/apt-network.conf"), "\r\n", "\n")
  }

  cloud_init = yamlencode({
    write_files = [
      {
        path        = "/usr/local/sbin/baytex-haproxy-reconcile"
        permissions = "0755"
        owner       = "root:root"
        content     = local.bootstrap_files.reconcile_script
      },
      {
        path        = "/etc/systemd/system/baytex-haproxy-reconcile.service"
        permissions = "0644"
        owner       = "root:root"
        content     = local.bootstrap_files.reconcile_service
      },
      {
        path        = "/etc/systemd/system/baytex-haproxy-reconcile.timer"
        permissions = "0644"
        owner       = "root:root"
        content     = local.bootstrap_files.reconcile_timer
      },
      {
        path        = "/etc/systemd/system/baytex-haproxy-frontend-ips.service"
        permissions = "0644"
        owner       = "root:root"
        content     = local.bootstrap_files.frontend_ips_service
      },
      {
        path        = "/etc/apt/apt.conf.d/99-baytex-network"
        permissions = "0644"
        owner       = "root:root"
        content     = local.bootstrap_files.apt_network_config
      },
      {
        # The load balancer uses floating IP. Non-local bind lets HAProxy bind a frontend IP before it is added to dummy0.
        path        = "/etc/sysctl.d/99-haproxy-nonlocal-bind.conf"
        permissions = "0644"
        owner       = "root:root"
        content     = "net.ipv4.ip_nonlocal_bind = 1\n"
      }
    ]
    # bootcmd runs on every boot. It enables the reconcile timer on a VM that restarted before runcmd ran on its first boot.
    # On the first boot itself it does nothing, because bootcmd runs before write_files has created the timer.
    bootcmd = [
      ["sh", "-c", "if [ -f /etc/systemd/system/baytex-haproxy-reconcile.timer ]; then systemctl enable --now baytex-haproxy-reconcile.timer; fi"]
    ]
    # runcmd runs once, on the first boot. The timer then starts the first reconcile within 30 seconds of boot.
    runcmd = [
      ["sysctl", "--system"],
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "baytex-haproxy-frontend-ips.service"],
      ["systemctl", "enable", "--now", "baytex-haproxy-reconcile.timer"]
    ]
  })
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

# Ubuntu LTS on Trusted Launch (secure boot and vTPM), SSH key authentication only, and platform-managed patching.
# The custom data carries the bootstrap and the user data carries the HAProxy configuration, as described in the locals above.
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
  custom_data                     = base64encode("#cloud-config\n${local.cloud_init}")
  user_data                       = base64encode(local.desired_state)
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  provision_vm_agent              = true
  patch_assessment_mode           = "AutomaticByPlatform"
  patch_mode                      = "AutomaticByPlatform"
  reboot_setting                  = "IfRequired"
  tags                            = var.tags

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

# Shows the rendered HAProxy configuration as a readable diff in the plan. The VMs receive it through their user data,
# which the plan can show only as an encoded value.
resource "terraform_data" "haproxy_config" {
  input = local.haproxy_config
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

# Probes the HAProxy health frontend, so a VM leaves the pool as soon as HAProxy stops answering.
resource "azurerm_lb_probe" "haproxy" {
  name                = "probe-haproxy-8404"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Tcp"
  port                = 8404
  interval_in_seconds = 5
  number_of_probes    = 2
  probe_threshold     = 1
}

# Floating IP keeps the frontend IP as the destination address, so each HAProxy frontend binds to its own frontend IP and port.
# Outbound SNAT is disabled because the load balancer carries no outbound traffic.
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

# Raised while fewer than all HAProxy VMs answer the health probe on port 8404, such as while a VM is still installing
# HAProxy, and resolved automatically once both answer again.
resource "azurerm_monitor_metric_alert" "health_probe" {
  count = var.enable_health_probe_alert ? 1 : 0

  name                = "alert-${var.name_prefix}-proxy-health-probe"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_lb.this.id]
  description         = "Fewer than all HAProxy VMs behind lb-${var.name_prefix}-proxy answer the health probe on port 8404."
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
