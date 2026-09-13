# Architecture and Ownership Boundaries

## Target flow

```text
Existing Baytex Hub / Connectivity Subscription
  Existing hub VNet
  Existing Cisco Firepower
  Existing VPN and on-premises routes
  Existing corporate DNS and central Private DNS zones
                |
        additive integration only
                |
New spoke per environment (DEV in Data Non-Production)
  - New resource groups and naming
  - Dedicated VNet and Databricks subnets
  - New Databricks workspace
  - New data storage and data Access Connector
  - Root Access Connector, when the default storage firewall is enabled
  - New NCC
  - New two-node HAProxy/ILB/PLS tier
  - New Terraform state and pipeline
```

## AMTRA Terraform ownership

- Environment resource groups
- VNet, subnets, NSGs, route tables, NAT Gateway
- VNet peering with the hub, for each direction enabled in tfvars
- Azure Databricks workspace and Azure platform settings
- ADLS Gen2 data foundation
- Access Connectors and required Azure RBAC
- Private endpoints in the spoke VNet, and their Private DNS zone groups when zone IDs are supplied
- HAProxy VMs, Load Balancer, and Private Link Services
- Databricks NCC and private endpoint rules
- Log Analytics and platform diagnostics
- Terraform modules, state, outputs, and CI/CD

## Baytex Infrastructure ownership

- Existing hub VNet, and the hub-side peering when `create_hub_to_spoke_peering` is `false`
- Cisco Firepower and its policy/rules
- Existing VPN and on-premises connectivity
- On-premises return routes
- Corporate DNS and central Private DNS zones, including their VNet links
- Role assignments in the hub subscription for the deployment service principal, when Terraform manages the peering or Private DNS registration
- Subscription governance
- Endpoint security/monitoring agent onboarding
- Production change control and operational approvals

## Hub-subscription integration

Two integrations with the hub subscription are optional and are enabled in tfvars. Each needs one role for the deployment service principal, granted by Baytex Infrastructure:

| Integration | tfvars | Role and scope |
| --- | --- | --- |
| VNet peering, in either direction | `hub_vnet_id`, `create_spoke_to_hub_peering`, `create_hub_to_spoke_peering` | Network Contributor on the hub VNet |
| Private DNS registration of the storage private endpoints | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

With both peering flags `false` and both zone lists empty, Terraform makes no calls to the hub subscription and needs no role there. The grant commands are in [GITHUB-SETUP.md](../GITHUB-SETUP.md) §2.

## Baytex BI ownership

- Existing regional Unity Catalog metastore
- Metastore assignment approval/operation
- Catalogs, schemas, grants, workspace bindings
- Storage credentials and external locations
- Entra groups used inside Unity Catalog
- Databricks Asset Bundles, notebooks, jobs, pipelines
- Data migration and business validation
- Power BI/Excel/report migration

## Existing resources

Existing Azure and Databricks resources are excluded from the Terraform state created by this repository. They remain operational and are reference-only.
