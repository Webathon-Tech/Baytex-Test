# Documentation

The documents for the Baytex Azure Databricks platform, grouped by the stage in which they are used. For an overview of
the project and what it delivers, start with the [repository README](../README.md).

## Understand

| Document | Purpose |
| --- | --- |
| [Architecture and boundaries](architecture-and-boundaries.md) | Design, network layout, traffic flows, resources in each environment, identities and ownership |
| [Configuration reference](configuration-reference.md) | Configuration model, input validation, naming, tags, every input and output |

## Prepare

| Document | Purpose |
| --- | --- |
| [Required inputs](required-inputs.md) | Decisions and values to collect and approve for each environment |
| [GitHub setup](github-setup.md) | Deployment identities, GitHub Environments, variables and protection rules |
| [Pre-deployment checklist](pre-deployment-checklist.md) | Sign-off before an environment's first apply |

## Deploy and operate

| Document | Purpose |
| --- | --- |
| [Deployment runbook](deployment-runbook.md) | Gated procedure for deploying and promoting an environment |
| [Workflows](workflows.md) | Running, approving and troubleshooting the pipelines |
| [Local runs](local-runs.md) | Planning and applying from a workstation |

## Hand off and accept

| Document | Purpose |
| --- | --- |
| [Firewall and DNS handoff](firewall-and-dns-handoff.md) | Network changes Baytex Infrastructure completes |
| [Unity Catalog handoff](unity-catalog-handoff.md) | Unity Catalog configuration Baytex BI completes |
| [Validation and acceptance](validation-notes.md) | Automated checks and the acceptance criteria for each environment |
