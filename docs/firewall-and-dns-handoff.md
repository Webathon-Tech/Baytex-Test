# Baytex Firewall, Peering, Routing, and DNS Handoff

Terraform does not modify the existing hub VNet, Cisco firewall, VPN, or on-premises network.

After the DEV plan is approved, provide Baytex Infrastructure with the Terraform outputs:

- `dev_vnet_id`
- `dev_vnet_cidr`
- `hub_side_peering_command`
- `firewall_handoff`
- `private_link_service_ids`
- `on_prem_destination_matrix`

Baytex Infrastructure must complete:

1. Hub-to-DEV peering with forwarded traffic enabled.
2. Cisco firewall address object(s) for the new DEV VNet/subnets.
3. Source/destination/port rules for the approved SQL and Oracle systems.
4. On-premises return routes for the new DEV CIDR.
5. Corporate DNS resolution from Azure to the on-premises FQDNs.
6. Private DNS zone links or equivalent central DNS changes for the storage private endpoints.
7. Validation that traffic follows the expected symmetric path.

No default route to Cisco is created by this baseline. Internet and Azure control-plane egress use NAT Gateway. Only the approved on-premises routes use Cisco as the next hop. Change that design only after explicit approval and firewall capacity review.
