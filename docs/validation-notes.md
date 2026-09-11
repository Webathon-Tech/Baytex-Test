# Validation Notes

## Checks completed in the authoring environment

- Reviewed the generated repository structure and environment ownership boundaries.
- Parsed both GitHub Actions workflow files as YAML.
- Ran static delimiter, quoted-string, comment, and heredoc checks across all Terraform files.
- Confirmed that the AMTRA platform root contains no Terraform import blocks and no existing Production subscription resource IDs.
- Confirmed that existing shared infrastructure is represented only as input/reference data.

## Checks that must run in Baytex before approval

The authoring environment could not reach the Terraform Registry, Azure, or the Baytex Databricks account. The following are therefore mandatory in the Baytex repository/runner:

1. `terraform fmt -check -recursive`
2. `terraform init` against the DEV backend
3. `terraform validate`
4. Provider and module lock-file review
5. `terraform plan` using approved DEV inputs
6. IaC security/policy scan
7. Review that the plan creates only new DEV resources and the approved additive spoke peering
8. Private Link/NCC, Power BI, classic compute, serverless, HAProxy failover, DNS, firewall, and on-premises connectivity validation

Do not apply the example variable values without Baytex approval.

<!-- End-to-end check of the pull request path filter. Not for merge. -->
