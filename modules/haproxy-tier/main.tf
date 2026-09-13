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

  # Rendered configuration files.
  # Line endings are normalised to LF so the files work on Linux regardless of the operating system that runs Terraform.
  haproxy_config = replace(templatefile("${path.module}/templates/haproxy.cfg.tftpl", {
    dns_servers = var.dns_servers
    endpoints   = var.endpoints
  }), "\r\n", "\n")

  configure_lb_ips_script = replace(templatefile("${path.module}/templates/configure-lb-ips.sh.tftpl", {
    frontend_ips = local.frontend_ips
  }), "\r\n", "\n")

  configure_lb_ips_service = replace(templatefile("${path.module}/templates/lb-ips.service.tftpl", {}), "\r\n", "\n")

  install_script = replace(templatefile("${path.module}/templates/install-packages.sh.tftpl", {}), "\r\n", "\n")

  # cloud-init document passed to both VMs as custom data.
  # Any change to it replaces the VMs, because custom data can be set only when a VM is created.
  cloud_init = yamlencode({
    write_files = [
      {
        path        = "/etc/haproxy/haproxy.cfg"
        permissions = "0644"
        owner       = "root:root"
        content     = local.haproxy_config
      },
      {
        path        = "/usr/local/sbin/configure-baytex-lb-ips.sh"
        permissions = "0755"
        owner       = "root:root"
        content     = local.configure_lb_ips_script
      },
      {
        path        = "/usr/local/sbin/install-haproxy-packages.sh"
        permissions = "0755"
        owner       = "root:root"
        content     = local.install_script
      },
      {
        path        = "/etc/systemd/system/baytex-lb-ips.service"
        permissions = "0644"
        owner       = "root:root"
        content     = local.configure_lb_ips_service
      },
      {
        # The load balancer uses floating IP, so the frontend IPs become local only after baytex-lb-ips.service adds them to the dummy0 interface.
        # Non-local bind lets HAProxy start and bind those addresses regardless of which service starts first.
        path        = "/etc/sysctl.d/99-haproxy-nonlocal-bind.conf"
        permissions = "0644"
        owner       = "root:root"
        content     = "net.ipv4.ip_nonlocal_bind = 1\n"
      }
    ]
    runcmd = [
      # Apply non-local bind before HAProxy starts.
      ["sysctl", "--system"],
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "baytex-lb-ips.service"],
      # The proxy subnet reaches the package mirrors only through the firewall.
      # The install script retries every minute until the mirrors answer, so the VMs finish configuring as soon as that path is open.
      ["/usr/local/sbin/install-haproxy-packages.sh"],
      ["haproxy", "-c", "-f", "/etc/haproxy/haproxy.cfg"],
      ["systemctl", "enable", "haproxy"],
      # The package starts HAProxy as soon as it is installed.
      # reset-failed clears systemd's start limit from that first start, so the restart below always runs with the final configuration.
      ["systemctl", "reset-failed", "haproxy"],
      ["systemctl", "restart", "haproxy"]
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
  load_balancer_frontend_ip_configuration_ids = [
    one([for configuration in azurerm_lb.this.frontend_ip_configuration : configuration.id if configuration.name == "fe-${each.key}"])
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
