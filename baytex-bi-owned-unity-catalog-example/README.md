# Baytex BI Unity Catalog Reference

A reference implementation of the Unity Catalog layer for one platform environment. It is owned by Baytex BI, uses its
own Terraform state, and is not called by the platform roots or deployed by the pipelines. The handoff it implements is
described in [docs/unity-catalog-handoff.md](../docs/unity-catalog-handoff.md).

## What it creates

- An environment-specific catalog whose managed storage is a folder under the platform's external location, in the
  environment's data storage account rather than the workspace's default storage
- Schemas in the catalog
- Workspace bindings that isolate the catalog to approved workspaces
- Grants to existing account-level groups and service principals

It creates no storage credential or external location: the platform creates both in every environment. Nor does it
assign the metastore, because Azure Databricks assigns every new workspace to the existing metastore when the
workspace is created.

Baytex BI owns the final naming, catalog structure, groups, grants, workspace bindings and cross-environment access
decisions.

## Inputs

Take the workspace and storage values from the platform's `unity_catalog_handoff` output:

| Input | `unity_catalog_handoff` field |
| --- | --- |
| `workspace_id` | `workspace_id` |
| `workspace_url` | `workspace_url` |
| `external_location_url` | `external_location_url` |

`terraform.tfvars.example` lists every input in the section order of `variables.tf`, with comments.

## Run

Sign in with the Azure CLI as an identity that holds `CREATE CATALOG` on the metastore and `CREATE_MANAGED_STORAGE` on
the platform's external location, or is a metastore administrator, configure a separate backend for this state, then:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out uc.tfplan
terraform apply uc.tfplan
```

## Notes

- Run it against the environment's own workspace. The platform's external location is isolated to that workspace, so a
  catalog placed in it cannot be created from another.
- Grant privileges to groups, not to individual users.
- Each catalog takes its own folder under the external location, so catalogs never share managed storage.
- A workspace binding changes the catalog from all-workspace access to explicitly bound workspaces only.
