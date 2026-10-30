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
  Two zonal HAProxy VMs, internal load balancer and Private Link Services
  Network Connectivity Configuration (Databricks account level)
  Unity Catalog storage credential and external location on the data storage account
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
  `proxy_nsg_rules`, and, while `proxy_deny_other_vnet_inbound` is `true` (the default), denies everything else arriving
  from the virtual network.
- **No implicit outbound access** — every subnet disables Azure's default outbound access, so traffic leaves only
  through the NAT Gateway or the firewall.

### What a network security group can and cannot close

Azure admits traffic from the `VirtualNetwork` tag by default, and that tag covers the spoke, the hub and every network
reached through it. With `proxy_deny_other_vnet_inbound` set to `true`, the default, the platform closes that on the
proxy subnet with a deny rule at the last available priority, so only the flows listed above reach the HAProxy VMs.

The Databricks subnets are different. Azure Databricks maintains its own rule on them, at priority 100, that allows any
traffic from the `VirtualNetwork` tag to any port, and a rule below priority 100 cannot be written. That rule is part of
VNet injection and Databricks restores it if it is removed, so inbound traffic from the virtual network to the Databricks
subnets cannot be restricted with a network security group. Traffic into them from the hub, the other spokes and
on-premises networks is controlled instead by Baytex's routing and Cisco firewall rules, and classic compute has no
public IP addresses.

The private endpoint subnet has no network security group. Private endpoint network policies are disabled on it, which is
the documented Azure pattern for a subnet that holds only private endpoints, and a network security group would not be
applied to the endpoints while they are disabled.

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

Each HAProxy VM is prepared by cloud-init when it is created. HAProxy itself comes from the Ubuntu package mirrors,
which the proxy subnet reaches through the firewall, so both the cloud-init install and the Custom Script Extension are
governed by `configure_haproxy`. While it is `false` the tier is deployed in full — VMs, load balancer, frontends and
Private Link Services — but HAProxy is not installed, the VMs fail the health probe and stay out of the backend pool,
and the tier serves no traffic. Every other part of the platform is unaffected, so an environment can be built before
the proxy subnet has outbound access.

With `configure_haproxy` set to `true`, cloud-init installs HAProxy as the VM is created and the Custom Script Extension
applies the HAProxy configuration and the load balancer frontend IPs. The extension runs again during any apply that
changes the destinations or DNS servers, so those changes update the VMs in place. A new configuration replaces the
running one only after `haproxy -c` accepts it, and HAProxy reloads without dropping established connections. The
configuration, the frontend IPs and the HAProxy service are all persistent operating system settings, so a restarted VM
rejoins the pool as soon as it has booted.

Azure Update Manager installs critical and security updates on the HAProxy VMs every Sunday afternoon, Alberta Time,
one VM after the other: 14:00–16:00 for the zone 1 VM and 18:00–20:00 for the zone 2 VM. A VM restarts only when an
update requires it. The two VMs are never patched at the same time, and a zone 1 VM that has not come back raises the
health probe alert before the zone 2 window opens.

The tier is built to keep serving through the loss of a VM or an availability zone. The load balancer requests the
HAProxy health frontend over HTTP every five seconds and takes a VM out of the pool after one failed probe, so the VM in
the other zone carries all traffic while one VM or zone is unavailable. A connection that reaches the load balancer
idle timeout receives a TCP reset, and HAProxy sends TCP keepalives on both sides, so long-lived database sessions stay
open through the load balancer, Private Link and firewall idle timers.

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
| `network` | Spoke VNet, subnets, network security groups, NAT Gateway and its public IP, route tables, spoke-side peering, NAT Gateway alerts |
| `platform` | Azure Databricks workspace |
| `dbx-managed` | Created and managed by Azure Databricks: the workspace root storage account, with the network access Azure Databricks gives it, and classic compute resources |
| `data` | Data storage account and containers, blob and dfs private endpoints, data Access Connector and its role assignments, storage availability alert |
| `connectivity` | HAProxy network interfaces, VMs, disks and configuration extensions, patch maintenance configurations, internal load balancer, Private Link Services, load balancer and HAProxy VM alerts |
| `ops` | Log Analytics workspace, alert action group when receivers are configured |
| `tfstate` | Terraform state storage account, created by the bootstrap root |

At the Databricks account level, each environment also has a Network Connectivity Configuration with its workspace
binding, its private endpoint rules and the network policy attached to the workspace. All of them are created by the
`ncc` module, because they are account-level resources bound to the same workspace. In the hub subscription, Terraform
manages only the optional hub-side peering and Private DNS records described below.

In the Unity Catalog metastore, the same module creates two objects through the workspace:

| Object | Name | Purpose |
| --- | --- | --- |
| Storage credential | `sc_bte_dbx_<env>_data_cnc_<instance>` | Backed by the data Access Connector |
| External location | `el_bte_dbx_<env>_data_cnc_<instance>` | Covers `abfss://unity-catalog@<data storage account>.dfs.core.windows.net/`, where catalogs and schemas can keep their managed storage, and where external tables and volumes can live |

Every environment's workspace is assigned to the same metastore, so both objects are isolated to their own
environment's workspace. The platform creates no catalogs or schemas. The workspace catalog Azure Databricks creates
with each new workspace stays in the workspace's default storage.

Both objects are created through the workspace, with its own URL, so Terraform creates them only after the workspace
exists and the platform has confirmed it is assigned to `existing_metastore_id`, and destroys them before the
workspace. Replacing the workspace needs them switched off first, as described in the
[configuration reference](configuration-reference.md#switching-the-unity-catalog-objects-off).

### Identities and access

| Identity | Access | Purpose |
| --- | --- | --- |
| Deployment service principal, `app-bte-dbx-<env>-terraform-001` (one per environment) | Contributor, Storage Blob Data Contributor and Role Based Access Control Administrator on the environment subscription; Databricks account admin; `CREATE STORAGE CREDENTIAL` and `CREATE EXTERNAL LOCATION` on the metastore | Runs every pipeline through GitHub OIDC, approves the NCC private endpoint connections after each deploy, and owns the storage credential and external location it creates |
| Data Access Connector | Storage Blob Data Contributor, Storage Account Contributor, Storage Queue Data Contributor and EventGrid EventSubscription Contributor on the data storage account | Backs the platform's Unity Catalog storage credential; the last three roles cover Auto Loader file events, which are off on the external location |
| HAProxy VMs | System-assigned managed identities with no role assignments | Available for agent onboarding |

## Hub-subscription integration

Two integrations with the hub subscription are optional. Both are off by default, and either can be enabled in an
environment's `terraform.tfvars`. Each needs one role for that environment's deployment service principal, granted by
Baytex Infrastructure:

| Integration | tfvars | Role and scope |
| --- | --- | --- |
| VNet peering, in either direction | `hub_vnet_id`, `create_spoke_to_hub_peering`, `create_hub_to_spoke_peering` | Network Contributor on the hub VNet |
| Private DNS registration of the storage private endpoints | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

Terraform addresses the hub VNet and the zones by their full resource IDs, so the service principal needs no other
access to the hub subscription. With both peering flags `false` and both zone lists empty, Terraform makes no calls to
the hub subscription at all. The grant commands are in [GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription).

Baytex owns both integrations, so every environment leaves them at their defaults: the peering flags `false` and the
zone lists empty. Baytex creates the peering in both directions, creates the Private DNS zones and adds the record sets for the
storage private endpoints. The storage private endpoints take static addresses from `blob_private_endpoint_ip` and
`dfs_private_endpoint_ip`, so those records stay correct when an environment is rebuilt.

## Ownership

### AMTRA — platform foundation in this repository

- Environment resource groups, VNet, subnets, network security groups, route tables and NAT Gateway
- VNet peering with the hub, only for a direction enabled in `terraform.tfvars` (none by default)
- Azure Databricks workspace and its Azure settings
- ADLS Gen2 data foundation, Access Connectors and their Azure role assignments
- Private endpoints in the spoke, at the static addresses configured for them, and their Private DNS zone groups when
  zone IDs are supplied (none by default)
- The Databricks network policy that limits serverless internet egress, and its attachment to the workspace
- HAProxy VMs, load balancer and Private Link Services
- Databricks Network Connectivity Configuration, private endpoint rules and the approval of their connections
- The Unity Catalog storage credential and external location over each environment's data storage account, and any
  grants on the location listed in `terraform.tfvars` (none by default)
- Log Analytics and platform diagnostics
- Terraform modules, state, outputs and pipelines

### Baytex Infrastructure — shared network and governance

- Existing hub VNet, and the VNet peering between the hub and each spoke in both directions
- Corporate DNS, and the central Private DNS zones with their VNet links and the record sets for the storage private
  endpoints
- Cisco firewall policy and rules, including spoke traffic to on-premises resources and to the other spokes
- VPN and on-premises connectivity, including return routes to each spoke
- Connectivity testing from Databricks once the network changes are in place
- Hub-subscription role assignments for the deployment service principals, when Terraform manages peering or DNS
  registration
- Subscription governance, endpoint security and monitoring agent onboarding
- Change control and operational approvals

### Baytex BI — data governance and workloads

- Existing regional Unity Catalog metastore, which Azure Databricks assigns each new workspace to automatically
- Catalogs, schemas, grants and workspace bindings, with catalog managed storage placed in the platform's external
  location
- Any further storage credentials and external locations
- Microsoft Entra groups used in Unity Catalog
- Databricks Asset Bundles, notebooks, jobs and pipelines
- Data migration, business validation and report migration

## Existing resources

Existing Azure and Databricks resources are not imported into the Terraform state of this repository, and are never
renamed, modified or destroyed by it. They remain operational and serve as reference only.
