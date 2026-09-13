# Firewall, Peering, Routing and DNS Handoff

The network changes Baytex Infrastructure completes for each environment, and the two optional hub integrations
Terraform can manage instead.

## What Terraform manages in the hub subscription

Terraform does not modify the Cisco firewall, the VPN or the on-premises network. In the hub subscription it manages
only two optional items, each enabled in the environment's `TFVARS` once Baytex grants the matching role
([GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription)):

| Item | Enabled by | Role for the deployment service principal |
| --- | --- | --- |
| VNet peering on the hub VNet, and the spoke-side peering to it | `create_hub_to_spoke_peering = true`, `create_spoke_to_hub_peering = true` | Network Contributor on the hub VNet |
| A records for the storage private endpoints in the hub Private DNS zones | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

## Terraform outputs for the handoff

After the environment's plan is approved, provide Baytex Infrastructure with these outputs:

| Output | Use |
| --- | --- |
| `vnet_id`, `vnet_cidr` | The spoke VNet and its address space |
| `firewall_handoff` | Source subnets, next hop, on-premises routes, default-route subnets, destination matrix and the required return route |
| `private_link_service_ids` | The Private Link Services serverless compute connects through |
| `hub_side_peering_command` | The Azure CLI command for the hub-side peering, set only when Terraform does not create it |

## Changes Baytex Infrastructure completes

1. **Hub-side peering** to the spoke VNet with forwarded traffic allowed, unless `create_hub_to_spoke_peering` is `true`.
2. **Firewall address objects** for the environment's VNet and subnets.
3. **Firewall rules** from the Databricks subnets and the proxy subnet to each approved SQL Server and Oracle
   destination and port, following the destination matrix.
4. **Firewall rules** from the proxy subnet to the Ubuntu package mirrors over TCP 80 and 443. The HAProxy VMs install
   their packages at first boot and take patches this way, and retry every minute until the rule exists.
5. **Return routes** from the on-premises networks to the environment's address space.
6. **Corporate DNS resolution** from Azure to the on-premises domain names.
7. **Private DNS records** for the storage private endpoints, unless the zone IDs are set, and in either case the links
   between the central Private DNS zones and the VNets that resolve them.
8. **Path validation** that traffic follows the expected symmetric path.

## Routing in the spoke

| Subnets | Route table | Sent to the firewall | Everything else |
| --- | --- | --- | --- |
| Databricks host and container | `databricks` | The prefixes in `on_prem_routes` | NAT Gateway, for the internet and the Databricks control plane |
| Private endpoints and proxy | `default` | All traffic, `0.0.0.0/0` | — |

Serverless connections to on-premises destinations reach the firewall from the proxy subnet, after passing through the
Private Link Service and HAProxy. Classic compute connections reach it directly from the Databricks subnets.
