# Firewall, Peering, Routing and DNS Handoff

The network changes Baytex Infrastructure completes for each environment, and the two hub integrations Terraform can
manage instead.

## Division of work

Terraform does not modify the Cisco firewall, the VPN or the on-premises network. Two items in the hub subscription can
be managed by Terraform, and every environment is delivered with both switched off, so Baytex owns them:

| Item | tfvars | Delivered as | Role Terraform would need |
| --- | --- | --- | --- |
| VNet peering between the hub and the spoke, in either direction | `create_spoke_to_hub_peering`, `create_hub_to_spoke_peering` | `false`, so Baytex creates both directions | Network Contributor on the hub VNet |
| A records for the storage private endpoints in the hub Private DNS zones | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Empty, so Baytex creates the zones and records | Private DNS Zone Contributor on each zone |

To move either one to Terraform later, Baytex grants the matching role
([GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription)) and the values are set in the environment's
`TFVARS`. While both are off, Terraform makes no calls to the hub subscription at all.

## Changes Baytex Infrastructure completes

1. **Private DNS zones** in the hub or connectivity subscription, with their links to the VNets that resolve them.
2. **Record sets** in those zones for the storage private endpoints, using the addresses in the `firewall_handoff`
   output. The endpoints take static addresses, so these records stay correct when an environment is rebuilt.
3. **VNet peering in both directions** between the hub VNet and the spoke VNet, with forwarded traffic allowed. The
   spoke has no gateway of its own and reaches on-premises networks through the firewall, so gateway transit is not
   used.
4. **Firewall address objects** for the environment's VNet and subnets.
5. **Firewall rules from the spoke to on-premises resources**, from the Databricks subnets and the proxy subnet to each
   approved SQL Server and Oracle destination and port, following the destination matrix.
6. **Firewall rules from the spoke to the other Azure spokes**, for the traffic the aggregate route sends to the
   firewall.
7. **Firewall rules from the proxy subnet to the Ubuntu package mirrors**, `archive.ubuntu.com` and
   `security.ubuntu.com`, over TCP 80 and 443. The HAProxy VMs install HAProxy and take platform patches this way.
   Until the rule exists, they retry the installation every two minutes, including across restarts.
8. **Return routes** from the on-premises networks to the environment's address space.
9. **Corporate DNS resolution** from Azure to the on-premises domain names.
10. **Path validation** that traffic follows the expected symmetric path.
11. **Connectivity tests from Databricks**, from both classic and serverless compute, to each approved destination.

## Terraform outputs for the handoff

After the environment's plan is approved, provide Baytex Infrastructure with these outputs:

| Output | Use |
| --- | --- |
| `vnet_id`, `vnet_cidr` | The spoke VNet and its address space |
| `firewall_handoff` | Source subnets, next hop, routes, default-route subnets, private endpoint addresses, destination matrix and the required return route |
| `data_private_endpoint_ips` | The addresses for the blob and dfs record sets |
| `private_link_service_ids` | The Private Link Services serverless compute connects through |
| `network_security_group_names` | The network security groups on the Databricks and proxy subnets |
| `hub_side_peering_command` | The Azure CLI command for the hub-side peering, set only when Terraform does not create it |

## Routing in the spoke

| Subnets | Route table | Sent to the firewall | Everything else |
| --- | --- | --- | --- |
| Databricks host and container | `databricks` | The prefixes in `firewall_routes` | NAT Gateway, for the internet and the Databricks control plane |
| Private endpoints and proxy | `default` | All traffic, `0.0.0.0/0` | — |

`firewall_routes` carries one aggregate prefix covering the Azure address range, so traffic to any other spoke reaches
the firewall without a route per spoke and a new spoke needs no change in Terraform. Azure selects the longest matching
prefix, so the aggregate never captures traffic that belongs to a more specific route: the spoke's own address space
stays local, and the hub range learned from the peering keeps the firewall itself reachable. The remaining prefixes are
the on-premises ranges and the vendor VPN host.

Serverless connections to on-premises destinations reach the firewall from the proxy subnet, after passing through the
Private Link Service and HAProxy. Classic compute connections reach it directly from the Databricks subnets.

## Outbound destinations

Approved outbound destinations are enforced in two places, because serverless and classic compute leave the platform by
different paths ([Architecture and boundaries](architecture-and-boundaries.md#controlling-outbound-destinations)).

- **Serverless compute** is limited by the Databricks network policy, which matches destinations by domain name. No
  firewall change is needed for it.
- **Classic compute** leaves through the NAT Gateway. Destinations that Azure publishes as a service tag are recorded in
  `databricks_nsg_rules`; the rest are allowed on the firewall, by name, where the firewall inspects the connection.

The Azure Databricks control-plane ranges published for the Genie app in Microsoft Teams are reached by Teams rather
than by the spoke, so they are allowed on the corporate firewall path that Teams uses. They are also recorded in
`databricks_nsg_rules` so the approved list is visible in one place.
