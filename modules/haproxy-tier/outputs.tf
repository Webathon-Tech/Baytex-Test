# ----------------------------------------------------------------------------------------------------------------------
# Load balancer and virtual machines
# ----------------------------------------------------------------------------------------------------------------------

output "load_balancer_id" {
  description = "Resource ID of internal load balancer 1."
  value       = azurerm_lb.this.id
}

output "additional_load_balancer_ids" {
  description = "Resource IDs of the internal load balancers after the first, keyed by their two-digit number. Empty while every destination is on load balancer 1."
  value       = { for key, lb in azurerm_lb.additional : key => lb.id }
}

output "backend_pool_id" {
  description = "Resource ID of the backend pool of internal load balancer 1."
  value       = azurerm_lb_backend_address_pool.this.id
}

output "proxy_vm_ids" {
  description = "Resource IDs of the HAProxy VMs, keyed by node number."
  value       = { for key, vm in azurerm_linux_virtual_machine.proxy : key => vm.id }
}

output "proxy_vm_private_ips" {
  description = "Private IPs of the HAProxy VMs, keyed by node number."
  value       = { for key, nic in azurerm_network_interface.proxy : key => nic.ip_configuration[0].private_ip_address }
}

# ----------------------------------------------------------------------------------------------------------------------
# Private Link Services
# ----------------------------------------------------------------------------------------------------------------------

output "private_link_service_ids" {
  description = "Resource IDs of the Private Link Services, keyed by destination name."
  value       = { for key, pls in azurerm_private_link_service.endpoint : key => pls.id }
}

output "private_link_services" {
  description = "Private Link Service ID, domain names, target and frontend IP of each destination, keyed by destination name. Used to build the NCC private endpoint rules."
  value = {
    for key, pls in azurerm_private_link_service.endpoint : key => {
      id           = pls.id
      domain_names = [var.endpoints[key].domain_name]
      target_fqdn  = var.endpoints[key].target_fqdn
      target_port  = var.endpoints[key].target_port
      frontend_ip  = var.endpoints[key].frontend_ip
    }
  }
}
