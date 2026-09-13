# Baytex Firewall, Peering, Routing, and DNS Handoff

Terraform does not modify the Cisco firewall, VPN or on-premises network. In the hub subscription it manages only two optional items, each enabled in tfvars once Baytex grants the matching role ([GITHUB-SETUP.md](../GITHUB-SETUP.md) §2):

| Item | Enabled by | Role for the deployment service principal |
| --- | --- | --- |
| VNet peering on the hub VNet, and the spoke-side peering to it | `create_hub_to_spoke_peering = true`, `create_spoke_to_hub_peering = true` | Network Contributor on the hub VNet |
| A records for the storage private endpoints in the hub Private DNS zones | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

After the DEV plan is approved, provide Baytex Infrastructure with the Terraform outputs:

- `vnet_id`
- `vnet_cidr`
- `hub_side_peering_command`, set only when Terraform does not create the hub-side peering
- `firewall_handoff`
- `private_link_service_ids`

Baytex Infrastructure must complete:

1. Hub-to-DEV peering with forwarded traffic enabled, unless `create_hub_to_spoke_peering` is `true`.
2. Cisco firewall address object(s) for the new DEV VNet/subnets.
3. Source/destination/port rules for the approved SQL and Oracle systems.
4. On-premises return routes for the new DEV CIDR.
5. Corporate DNS resolution from Azure to the on-premises FQDNs.
6. DNS records for the storage private endpoints, unless the zone IDs are set, and in either case the links between the central Private DNS zones and the resolving VNets.
7. Validation that traffic follows the expected symmetric path.
8. Firewall rules letting the proxy subnet reach the Ubuntu package mirrors over TCP 80 and 443. The HAProxy VMs install their packages at first boot and take patches this way; until the rule exists they retry every minute.

Two route tables are created. The Databricks host and container subnets send only the approved on-premises routes to Cisco, and reach the internet and the Azure control plane through the NAT Gateway. The proxy and private endpoint subnets send all traffic, `0.0.0.0/0`, to Cisco.
