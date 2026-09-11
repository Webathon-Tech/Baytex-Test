# Baytex BI-owned Unity Catalog reference

This folder is a **reference implementation only**. It is intentionally separate from the AMTRA platform root and must use a separate Terraform backend/state if Baytex BI chooses to adopt it.

It demonstrates Option B:

- Assign the new DEV workspace to the **existing regional metastore**.
- Create an environment-specific storage credential backed by the AMTRA-created data Access Connector (the `data_access_connector_id` platform output).
- Create separate managed and external storage locations.
- Create an environment-specific catalog and schemas.
- Isolate the catalog, external locations, and storage credential to approved workspaces.
- Grant permissions only to existing account-level groups/service principals.

Baytex BI owns the final naming, catalog structure, groups, grants, workspace bindings, and cross-environment access decisions. AMTRA does not call this configuration from the platform deployment.

## Run

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out uc-dev.tfplan
terraform apply uc-dev.tfplan
```

## Important

- Confirm the new workspace is in the same Azure region as the existing metastore.
- Use group-based permissions, not direct user grants.
- The managed catalog storage root is placed under a registered external location, as required by Unity Catalog.
- A workspace binding changes the securable from all-workspace access to explicitly bound workspaces only.
- Read-only bindings are supported only for catalogs; storage credentials and external locations use read-write bindings.
