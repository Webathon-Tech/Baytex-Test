# Baytex Firewall, Peering, Routing, and DNS Handoff

Terraform does not modify the existing hub VNet, Cisco firewall, VPN, or on-premises network.

After the DEV plan is approved, provide Baytex Infrastructure with the Terraform outputs:

- `dev_vnet_id`
- `dev_vnet_cidr`
- `hub_side_peering_command`
- `firewall_handoff`
- `private_link_service_ids`

Baytex Infrastructure must complete:

1. Hub-to-DEV peering with forwarded traffic enabled.
2. Cisco firewall address object(s) for the new DEV VNet/subnets.
3. Source/destination/port rules for the approved SQL and Oracle systems.
4. On-premises return routes for the new DEV CIDR.
5. Corporate DNS resolution from Azure to the on-premises FQDNs.
6. Private DNS zone links or equivalent central DNS changes for the storage private endpoints.
7. Validation that traffic follows the expected symmetric path.
8. Firewall rules letting the proxy subnet reach the Ubuntu package mirrors over TCP 80 and 443. The HAProxy VMs install their packages at first boot and take patches this way; until the rule exists they retry every minute.

Two route tables are created. The Databricks host and container subnets send only the approved on-premises routes to Cisco, and reach the internet and the Azure control plane through the NAT Gateway. The proxy and private endpoint subnets send all traffic, `0.0.0.0/0`, to Cisco.
