output "load_balancer_id" { value = azurerm_lb.this.id }
output "backend_pool_id" { value = azurerm_lb_backend_address_pool.this.id }
output "proxy_vm_ids" { value = { for key, vm in azurerm_linux_virtual_machine.proxy : key => vm.id } }
output "proxy_vm_private_ips" { value = { for key, nic in azurerm_network_interface.proxy : key => nic.ip_configuration[0].private_ip_address } }
output "private_link_service_ids" { value = { for key, pls in azurerm_private_link_service.endpoint : key => pls.id } }
output "private_link_services" {
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
