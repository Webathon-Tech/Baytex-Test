# Unity Catalog handoff — Option B

The AMTRA platform deployment creates Azure resources only and emits a `unity_catalog_handoff` output. Baytex BI owns the Unity Catalog layer.

## AMTRA provides

- Existing Databricks account ID supplied as input
- Existing regional metastore ID supplied as input
- New DEV workspace ID, URL, and ARM resource ID
- DEV data Access Connector ID and principal ID
- DEV ADLS Gen2 account ID/name
- Managed, external, landing, and checkpoint container URLs

## Baytex BI completes

1. Confirm the new DEV workspace is assigned to the existing Canada Central metastore.
2. Create an environment-specific storage credential using the DEV data Access Connector.
3. Create separate managed and general-purpose external locations.
4. Create the DEV catalog and schemas.
5. Set securables to isolated mode and apply explicit workspace bindings.
6. Use account-level groups/service principals, not individual-user grants.
7. Define any future Test/Prod cross-workspace bindings and whether catalog access is read-only or read-write.
8. Validate storage, catalog, table, volume, and representative workload access.

The optional `baytex-bi-owned-unity-catalog-example` demonstrates this pattern in a separate Terraform state. AMTRA does not call or own it.
