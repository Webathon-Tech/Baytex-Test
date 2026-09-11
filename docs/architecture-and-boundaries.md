# Architecture and Ownership Boundaries

## Target flow

```text
Existing Baytex Hub / Connectivity Subscription
  Existing hub VNet
  Existing Cisco Firepower
  Existing VPN and on-premises routes
  Existing corporate DNS
                |
        additive integration only
                |
New DEV spoke in Data Non-Production subscription
  - New resource groups and naming
  - Dedicated VNet and Databricks subnets
  - New Databricks workspace
  - New data storage and two Access Connectors (workspace root, data)
  - New DEV NCC
  - New two-node HAProxy/ILB/PLS tier
  - New Terraform state and pipeline
```

## AMTRA Terraform ownership

- DEV resource groups
- DEV VNet, subnets, NSGs, route tables, NAT Gateway
- Spoke-side peering
- Azure Databricks workspace and Azure platform settings
- ADLS Gen2 data foundation
- Access Connectors and required Azure RBAC
- Private endpoints in the DEV VNet
- HAProxy VMs, Load Balancer, and Private Link Services
- Databricks NCC and private endpoint rules
- Log Analytics and platform diagnostics
- Terraform modules, state, outputs, and CI/CD

## Baytex Infrastructure ownership

- Existing hub VNet and hub-side peering
- Cisco Firepower and its policy/rules
- Existing VPN and on-premises connectivity
- On-premises return routes
- Corporate DNS and central Private DNS zones
- Provider registration and subscription governance
- Endpoint security/monitoring agent onboarding
- Production change control and operational approvals

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
