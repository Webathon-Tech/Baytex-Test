# Architecture and Ownership Boundaries

This document describes what the platform builds in each environment, how traffic flows through it, and who owns each
part of the solution.

## Overview

Each environment — dev, test and prod — is a self-contained spoke in its own Azure subscription. It connects additively
to the existing Baytex hub, which provides the Cisco firewall, the VPN to on-premises networks and corporate DNS. The
spoke contains everything the Databricks platform needs: networking, the workspace, a private data lake, a connectivity
tier that lets serverless compute reach on-premises databases, monitoring and its own Terraform state.

```text
Existing Baytex hub subscription
  Hub VNet, Cisco firewall, VPN and on-premises routes
  Corporate DNS and central Private DNS zones
                |
        additive integration only
                |
Environment spoke subscription (one per environment)
  Resource groups following the naming convention
  Spoke VNet with Databricks, private endpoint and proxy subnets
  Azure Databricks workspace (Premium, VNet-injected)
  ADLS Gen2 data storage with a data Access Connector
  Root Access Connector, attached to the workspace when the default storage firewall is enabled
  Two-node HAProxy tier, internal load balancer and Private Link Services
  Network Connectivity Configuration (Databricks account level)
  Log Analytics and diagnostic settings
  Terraform state storage account
```

## Network design

Each environment uses its own non-overlapping address space, typically a `/20`, so all three can peer with the same hub.

| Subnet | Typical size | Holds | Route table | Internet egress |
| --- | --- | --- | --- | --- |
| Databricks host | `/24` | Classic compute host interfaces, delegated to Azure Databricks | `databricks` | NAT Gateway |
| Databricks container | `/24` | Classic compute container interfaces, delegated to Azure Databricks | `databricks` | NAT Gateway |
| Private endpoints | `/26` | Blob and dfs private endpoints of the data storage account | `default` | Firewall |
| Proxy | `/26` | HAProxy VMs, load balancer frontends and Private Link Service NAT IPs | `default` | Firewall |

- **`databricks` route table** — sends only the prefixes in `firewall_routes` to the firewall. Everything else, including
  the Databricks control plane and artefact repositories, leaves through the NAT Gateway, so the firewall does not have
  to allow every Databricks endpoint.
- **`default` route table** — sends all traffic, `0.0.0.0/0`, to the firewall.
- **Network security groups** — the host and container groups are maintained by Databricks, and `databricks_nsg_rules`
  adds the environment's own rules to both. The proxy group allows the load balancer health probe, Private Link Service
  traffic on each listener port and, optionally, SSH from approved ranges, takes any further rules from
  `proxy_nsg_rules`, and then denies everything else arriving from the virtual network.

### What a network security group can and cannot close

Azure admits traffic from the `VirtualNetwork` tag by default, and that tag covers the spoke, the hub and every network
reached through it. The platform closes that on the proxy subnet with a deny rule at the last available priority, so only
the flows listed above reach the HAProxy VMs.

The Databricks subnets are different. Azure Databricks maintains its own rule on them, at priority 100, that allows any
traffic from the `VirtualNetwork` tag to any port, and a rule below priority 100 cannot be written. That rule is part of
VNet injection and Databricks restores it if it is removed, so inbound traffic from the virtual network to the Databricks
subnets cannot be restricted with a network security group. Those subnets are protected instead by having no inbound
route from outside the spoke and by the firewall rules that govern what may reach them.

The private endpoint subnet has no network security group. Private endpoint network policies are disabled on it, which is
the documented Azure pattern for a subnet that holds only private endpoints, and a network security group would not be
applied to the endpoints while they are disabled.
- **No implicit outbound access** — every subnet disables Azure's default outbound access, so traffic leaves only
  through the NAT Gateway or the firewall.

### Reaching the other Azure spokes

`firewall_routes` normally carries one aggregate prefix covering the whole Azure address range rather than a route per
spoke, so a new spoke needs no change here. Azure selects the longest matching prefix, so the aggregate never captures
traffic that belongs to a more specific route: the spoke's own address space stays local, and the hub range learned from
the peering keeps the next hop reachable.

## Traffic flows

| From | To | Path |
| --- | --- | --- |
| Classic compute | On-premises SQL Server and Oracle | Databricks subnets → `databricks` route table → Cisco firewall → hub → VPN → destination |
| Classic compute | Internet and Databricks control plane | Databricks subnets → NAT Gateway |
| Classic compute | Data storage | Private endpoints in the spoke private endpoint subnet |
| Serverless compute | On-premises SQL Server and Oracle | NCC private endpoint → Private Link Service → internal load balancer → HAProxy → Cisco firewall → hub → VPN → destination |
| Serverless compute | Data storage | NCC private endpoints on the storage account's blob and dfs endpoints |
| Serverless compute | Approved internet destinations | Databricks serverless network, governed by the account network policy |
| Users, Power BI, GitHub | Workspace front end | Public workspace URL, authenticated with Microsoft Entra ID |
| HAProxy VMs | Ubuntu package mirrors | Proxy subnet → Cisco firewall → internet |

HAProxy resolves each destination's fully qualified domain name through the corporate DNS servers at run time. The
destinations therefore return traffic to the proxy subnet, whose address range Baytex adds to its on-premises return
routes.

Terraform delivers the HAProxy configuration and the load balancer frontend IPs to both VMs through their user data. A
reconcile service on each VM applies them shortly after boot and every two minutes after that. It installs HAProxy once
the package mirrors are reachable, validates each new configuration with `haproxy -c` before a graceful reload, and
keeps the running configuration when a new one is rejected, so a change to the destinations or DNS servers updates the
VMs in place.

## Controlling outbound destinations

Approved outbound destinations are enforced in different places for the two kinds of compute, because the two leave the
platform by different paths.

| Compute | Leaves through | Enforced by | Matches on |
| --- | --- | --- | --- |
| Serverless | The Databricks serverless network | The account network policy, `serverless_allowed_internet_destinations` | Domain names |
| Classic | The spoke subnets and the NAT Gateway | Route tables, `databricks_nsg_rules` and the Cisco firewall | Addresses, CIDR ranges and service tags |

A network security group matches addresses, CIDR ranges and service tags; it has no way to match a domain name. A
destination that is only known by name is therefore expressed for serverless compute in the network policy, and for
classic compute either as a service tag, where Azure publishes one, or as a rule on the firewall.

Allow rules in `databricks_nsg_rules` record the approved destinations without restricting anything on their own,
because the Databricks subnets already reach the internet through the NAT Gateway. Restricting them takes a Deny rule
at a higher priority number than every Allow rule, added once every destination Databricks itself needs is covered.

## Resources in each environment

Resource names follow `<type>-<organization>-<workload>-<environment>-<purpose>-<region>-<instance>`, for example
`rg-bte-dbx-dev-network-cnc-001`. The full convention is in the
[configuration reference](configuration-reference.md#naming-convention).

| Resource group | Contents |
| --- | --- |
| `network` | Spoke VNet, subnets, network security groups, NAT Gateway and its public IP, route tables, spoke-side peering |
| `platform` | Azure Databricks workspace, root Access Connector |
| `dbx-managed` | Created and managed by Azure Databricks: the workspace root storage account and classic compute resources |
| `data` | Data storage account and containers, blob and dfs private endpoints, data Access Connector and its role assignments |
| `connectivity` | HAProxy network interfaces, VMs and disks, internal load balancer, Private Link Services |
| `ops` | Log Analytics workspace, alert action group when receivers are configured |
| `tfstate` | Terraform state storage account, created by the bootstrap root |

At the Databricks account level, each environment also has a Network Connectivity Configuration with its workspace
binding, its private endpoint rules and the network policy attached to the workspace. All of them are created by the
`ncc` module, because they are account-level resources bound to the same workspace. In the hub subscription, Terraform manages only the optional hub-side peering and
Private DNS records described below.

### Identities and access

| Identity | Access | Purpose |
| --- | --- | --- |
| Deployment service principal, `app-bte-dbx-<env>-terraform-001` (one per environment) | Contributor, Storage Blob Data Contributor and Role Based Access Control Administrator on the environment subscription; Databricks account admin | Runs every pipeline through GitHub OIDC, with no client secret |
| Data Access Connector | Storage Blob Data Contributor, Storage Account Contributor, Storage Queue Data Contributor and EventGrid EventSubscription Contributor on the data storage account | Backs the Unity Catalog storage credential and Auto Loader file events |
| Root Access Connector | Granted by Azure Databricks on the root storage account while it is attached | Accesses the workspace root storage when its firewall is enabled |
| HAProxy VMs | System-assigned managed identities with no role assignments | Available for agent onboarding |

## Hub-subscription integration

Two integrations with the hub subscription are optional and are enabled in each environment's `TFVARS`. Each needs one
role for that environment's deployment service principal, granted by Baytex Infrastructure:

| Integration | tfvars | Role and scope |
| --- | --- | --- |
| VNet peering, in either direction | `hub_vnet_id`, `create_spoke_to_hub_peering`, `create_hub_to_spoke_peering` | Network Contributor on the hub VNet |
| Private DNS registration of the storage private endpoints | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

Terraform addresses the hub VNet and the zones by their full resource IDs, so the service principal needs no other
access to the hub subscription. With both peering flags `false` and both zone lists empty, Terraform makes no calls to
the hub subscription at all. The grant commands are in [GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription).

Baytex owns both integrations, so every environment is configured with the peering flags `false` and the zone lists
empty. Baytex creates the peering in both directions, creates the Private DNS zones and adds the record sets for the
storage private endpoints. The storage private endpoints take static addresses from `blob_private_endpoint_ip` and
`dfs_private_endpoint_ip`, so those records stay correct when an environment is rebuilt.

## Ownership

### AMTRA — platform foundation in this repository

- Environment resource groups, VNet, subnets, network security groups, route tables and NAT Gateway
- VNet peering with the hub, for each direction enabled in `TFVARS`
- Azure Databricks workspace and its Azure settings
- ADLS Gen2 data foundation, Access Connectors and their Azure role assignments
- Private endpoints in the spoke, at the static addresses configured for them, and their Private DNS zone groups when
  zone IDs are supplied
- The Databricks network policy that limits serverless internet egress, and its attachment to the workspace
- HAProxy VMs, load balancer and Private Link Services
- Databricks Network Connectivity Configuration and private endpoint rules
- Log Analytics and platform diagnostics
- Terraform modules, state, outputs and pipelines

### Baytex Infrastructure — shared network and governance

- Existing hub VNet, and the VNet peering between the hub and each spoke in both directions
- The Private DNS zones and the record sets for the storage private endpoints
- Cisco firewall policy and rules, including spoke traffic to on-premises resources and to the other spokes
- VPN and on-premises connectivity, including return routes to each spoke
- Corporate DNS and central Private DNS zones, including their VNet links
- Connectivity testing from Databricks once the network changes are in place
- Hub-subscription role assignments for the deployment service principals, when Terraform manages peering or DNS
  registration
- Subscription governance, endpoint security and monitoring agent onboarding
- Change control and operational approvals

### Baytex BI — data governance and workloads

- Existing regional Unity Catalog metastore and its assignment to each workspace
- Catalogs, schemas, grants and workspace bindings
- Storage credentials and external locations
- Microsoft Entra groups used in Unity Catalog
- Databricks Asset Bundles, notebooks, jobs and pipelines
- Data migration, business validation and report migration

## Existing resources

Existing Azure and Databricks resources are not imported into the Terraform state of this repository, and are never
renamed, modified or destroyed by it. They remain operational and serve as reference only.
