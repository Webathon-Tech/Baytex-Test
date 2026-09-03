locals {
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

  # Every rendered template is CR-stripped before it reaches cloud-init.
  # On a Windows checkout (git core.autocrlf=true) these .tftpl files arrive with
  # CRLF endings, and templatefile() preserves them verbatim. A shell script that
  # begins "#!/usr/bin/env bash\r" then dies with:
  #     /usr/bin/env: 'bash\r': No such file or directory
  # which silently breaks the whole tier: configure-lb-ips never creates dummy0,
  # the load balancer frontend IPs are never bound, and HAProxy cannot bind its
  # listeners so it fails to start -- while terraform still reports success.
  # .gitattributes pins these files to LF; this replace() is the belt-and-braces
  # guard so the module is correct regardless of how the repo was checked out.
  haproxy_config = replace(templatefile("${path.module}/templates/haproxy.cfg.tftpl", {
    dns_servers = var.dns_servers
    endpoints   = var.endpoints
  }), "\r\n", "\n")

  configure_lb_ips_script = replace(templatefile("${path.module}/templates/configure-lb-ips.sh.tftpl", {
    frontend_ips = local.frontend_ips
  }), "\r\n", "\n")

  configure_lb_ips_service = replace(templatefile("${path.module}/templates/lb-ips.service.tftpl", {}), "\r\n", "\n")

  cloud_init = yamlencode({
    package_update = true
    packages       = ["haproxy", "rsyslog", "netcat-openbsd"]
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
        path        = "/etc/systemd/system/baytex-lb-ips.service"
        permissions = "0644"
        owner       = "root:root"
        content     = local.configure_lb_ips_service
      },
      {
        # The load balancer frontend IPs are floating-IP (DSR) addresses that
        # only become local once baytex-lb-ips.service adds them to dummy0.
        # Allowing non-local bind lets HAProxy start regardless of that
        # ordering, instead of dying with "Cannot assign requested address".
        path        = "/etc/sysctl.d/99-haproxy-nonlocal-bind.conf"
        permissions = "0644"
        owner       = "root:root"
        content     = "net.ipv4.ip_nonlocal_bind = 1\n"
      }
    ]
    runcmd = [
      # Apply non-local bind before HAProxy is (re)started.
      ["sysctl", "--system"],
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "baytex-lb-ips.service"],
      ["haproxy", "-c", "-f", "/etc/haproxy/haproxy.cfg"],
      ["systemctl", "enable", "haproxy"],
      # Installing the haproxy package starts it immediately, before the
      # frontend IPs exist. Those failures burn systemd's StartLimitBurst, and
      # a plain "restart" is then refused with "Start request repeated too
      # quickly" -- leaving the tier dead even though the config is valid.
      # reset-failed clears that rate limiter so the restart below is honoured.
      ["systemctl", "reset-failed", "haproxy"],
      ["systemctl", "restart", "haproxy"]
    ]
  })
}

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

resource "azurerm_linux_virtual_machine" "proxy" {
  for_each = local.proxy_nodes

  name                            = "vm-${var.name_prefix}-proxy-${each.key}"
  computer_name                   = "${var.name_prefix}-proxy-${each.key}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.proxy_vm_size
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
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}
}

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

resource "azurerm_lb_probe" "haproxy" {
  name                = "probe-haproxy-8404"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Tcp"
  port                = 8404
  interval_in_seconds = 5
  number_of_probes    = 2
  probe_threshold     = 1
}

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
    precondition {
      condition     = var.allow_all_subscriptions_visibility || length(var.visibility_subscription_ids) > 0
      error_message = "Provide explicit visibility_subscription_ids or set allow_all_subscriptions_visibility=true as an approved exception."
    }

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
