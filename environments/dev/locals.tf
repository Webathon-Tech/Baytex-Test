locals {
  # --------------------------------------------------------------------------------------------------------------------
  # Naming
  # --------------------------------------------------------------------------------------------------------------------

  resource_name_prefix = "${var.organization}-${var.workload}-${var.environment}-${var.region_short}-${var.instance}"

  # Azure limits an action group short name to 12 characters, so it is built from the workload and environment only.
  action_group_short_name = substr("${var.workload}${var.environment}", 0, 12)

  names = {
    rg_network      = "rg-${var.organization}-${var.workload}-${var.environment}-network-${var.region_short}-${var.instance}"
    rg_platform     = "rg-${var.organization}-${var.workload}-${var.environment}-platform-${var.region_short}-${var.instance}"
    rg_data         = "rg-${var.organization}-${var.workload}-${var.environment}-data-${var.region_short}-${var.instance}"
    rg_connectivity = "rg-${var.organization}-${var.workload}-${var.environment}-connectivity-${var.region_short}-${var.instance}"
    rg_ops          = "rg-${var.organization}-${var.workload}-${var.environment}-ops-${var.region_short}-${var.instance}"

    vnet                        = "vnet-${local.resource_name_prefix}"
    databricks_host_subnet      = "snet-${var.organization}-${var.workload}-${var.environment}-dbx-host-${var.region_short}-${var.instance}"
    databricks_container_subnet = "snet-${var.organization}-${var.workload}-${var.environment}-dbx-container-${var.region_short}-${var.instance}"
    private_endpoint_subnet     = "snet-${var.organization}-${var.workload}-${var.environment}-private-endpoints-${var.region_short}-${var.instance}"
    proxy_subnet                = "snet-${var.organization}-${var.workload}-${var.environment}-proxy-${var.region_short}-${var.instance}"

    workspace              = "dbw-${local.resource_name_prefix}"
    managed_resource_group = "rg-${var.organization}-${var.workload}-${var.environment}-dbx-managed-${var.region_short}-${var.instance}"
    access_connector_root  = "ac-${var.organization}-${var.workload}-${var.environment}-root-${var.region_short}-${var.instance}"
    access_connector_data  = "ac-${var.organization}-${var.workload}-${var.environment}-data-${var.region_short}-${var.instance}"
    ncc                    = "ncc-${local.resource_name_prefix}"
    network_policy         = "np-${local.resource_name_prefix}"
    log_analytics          = "log-${local.resource_name_prefix}"
    action_group           = "ag-${local.resource_name_prefix}"
  }

  # --------------------------------------------------------------------------------------------------------------------
  # Tags
  # --------------------------------------------------------------------------------------------------------------------

  tags = merge(
    {
      Application        = "AzureDatabricks"
      BusinessUnit       = "BI"
      Environment        = title(var.environment)
      ManagedBy          = "Terraform"
      Owner              = var.owner
      CostCentre         = var.cost_centre
      DataClassification = var.data_classification
      Project            = "Baytex Terraform Foundations"
    },
    var.additional_tags
  )

  # --------------------------------------------------------------------------------------------------------------------
  # Hub VNet
  # --------------------------------------------------------------------------------------------------------------------

  # Parts of hub_vnet_id, which has the form /subscriptions/<subscription>/resourceGroups/<resource group>/providers/Microsoft.Network/virtualNetworks/<name>.
  # Each value is null when hub_vnet_id is not set.
  hub_vnet = {
    subscription_id     = try(split("/", var.hub_vnet_id)[2], null)
    resource_group_name = try(split("/", var.hub_vnet_id)[4], null)
    name                = try(split("/", var.hub_vnet_id)[8], null)
  }

  # --------------------------------------------------------------------------------------------------------------------
  # On-premises connectivity
  # --------------------------------------------------------------------------------------------------------------------

  # The NCC module needs only the ID and domain names of each Private Link Service.
  private_link_services_for_ncc = {
    for key, value in module.haproxy.private_link_services : key => {
      id           = value.id
      domain_names = value.domain_names
    }
  }

  # One proxy NSG rule is created per distinct listener port.
  listener_ports = toset([for endpoint in values(var.on_prem_endpoints) : endpoint.listen_port])

  # Destination matrix reported in the firewall_handoff output.
  endpoint_matrix = {
    for key, endpoint in var.on_prem_endpoints : key => {
      domain_name = endpoint.domain_name
      target_fqdn = endpoint.target_fqdn
      target_port = endpoint.target_port
      listen_port = endpoint.listen_port
      access_from = ["${upper(var.environment)} serverless through NCC/PLS", "${upper(var.environment)} classic compute through VNet/UDR"]
    }
  }
}
