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
  Root Access Connector, when the default storage firewall is enabled
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

- **`databricks` route table** — sends only the prefixes in `on_prem_routes` to the firewall. Everything else, including
  the Databricks control plane and artefact repositories, leaves through the NAT Gateway, so the firewall does not have
  to allow every Databricks endpoint.
- **`default` route table** — sends all traffic, `0.0.0.0/0`, to the firewall.
- **Network security groups** — the host and container groups are maintained by Databricks. The proxy group allows the
  load balancer health probe, Private Link Service traffic on each listener port and, optionally, SSH from approved
  ranges.
- **No implicit outbound access** — every subnet disables Azure's default outbound access, so traffic leaves only
  through the NAT Gateway or the firewall.

## Traffic flows

| From | To | Path |
| --- | --- | --- |
| Classic compute | On-premises SQL Server and Oracle | Databricks subnets → `databricks` route table → Cisco firewall → hub → VPN → destination |
| Classic compute | Internet and Databricks control plane | Databricks subnets → NAT Gateway |
| Classic compute | Data storage | Private endpoints in the spoke private endpoint subnet |
| Serverless compute | On-premises SQL Server and Oracle | NCC private endpoint → Private Link Service → internal load balancer → HAProxy → Cisco firewall → hub → VPN → destination |
| Serverless compute | Data storage | NCC private endpoints on the storage account's blob and dfs endpoints |
| Users, Power BI, GitHub | Workspace front end | Public workspace URL, authenticated with Microsoft Entra ID |
| HAProxy VMs | Ubuntu package mirrors | Proxy subnet → Cisco firewall → internet |

HAProxy resolves each destination's fully qualified domain name through the corporate DNS servers at run time. The
destinations therefore return traffic to the proxy subnet, whose address range Baytex adds to its on-premises return
routes.

## Resources in each environment

Resource names follow `<type>-<organization>-<workload>-<environment>-<purpose>-<region>-<instance>`, for example
`rg-bte-dbx-dev-network-cnc-001`. The full convention is in the
[configuration reference](configuration-reference.md#naming-convention).

| Resource group | Contents |
| --- | --- |
| `network` | Spoke VNet, subnets, network security groups, NAT Gateway and its public IP, route tables, spoke-side peering |
| `platform` | Azure Databricks workspace, root Access Connector when the default storage firewall is enabled |
| `dbx-managed` | Created and managed by Azure Databricks: the workspace root storage account and classic compute resources |
| `data` | Data storage account and containers, blob and dfs private endpoints, data Access Connector and its role assignments |
| `connectivity` | HAProxy network interfaces, VMs and disks, internal load balancer, Private Link Services |
| `ops` | Log Analytics workspace, alert action group when receivers are configured |
| `tfstate` | Terraform state storage account, created by the bootstrap root |

At the Databricks account level, each environment also has a Network Connectivity Configuration with its workspace
binding and private endpoint rules. In the hub subscription, Terraform manages only the optional hub-side peering and
Private DNS records described below.

### Identities and access

| Identity | Access | Purpose |
| --- | --- | --- |
| Deployment service principal (one per environment) | Contributor, User Access Administrator and Storage Blob Data Contributor on the environment subscription; Databricks account admin | Runs every pipeline through GitHub OIDC, with no client secret |
| Data Access Connector | Storage Blob Data Contributor, Storage Account Contributor, Storage Queue Data Contributor and EventGrid EventSubscription Contributor on the data storage account | Backs the Unity Catalog storage credential and Auto Loader file events |
| Root Access Connector | Granted by Azure Databricks on the root storage account | Accesses the workspace root storage when its firewall is enabled |
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

## Ownership

### AMTRA — platform foundation in this repository

- Environment resource groups, VNet, subnets, network security groups, route tables and NAT Gateway
- VNet peering with the hub, for each direction enabled in `TFVARS`
- Azure Databricks workspace and its Azure settings
- ADLS Gen2 data foundation, Access Connectors and their Azure role assignments
- Private endpoints in the spoke, and their Private DNS zone groups when zone IDs are supplied
- HAProxy VMs, load balancer and Private Link Services
- Databricks Network Connectivity Configuration and private endpoint rules
- Log Analytics and platform diagnostics
- Terraform modules, state, outputs and pipelines

### Baytex Infrastructure — shared network and governance

- Existing hub VNet, and the hub-side peering when `create_hub_to_spoke_peering` is `false`
- Cisco firewall policy and rules
- VPN and on-premises connectivity, including return routes to each spoke
- Corporate DNS and central Private DNS zones, including their VNet links
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
