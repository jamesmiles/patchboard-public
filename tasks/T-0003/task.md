---
id: T-0003
title: "Write deployment architecture document"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0002
parallel_with: []
parent_epic: E-0001
acceptance:
  - "Deployment modes are documented (e.g. local dev, hosted environments)"
  - "Hosted architecture is described — services, databases, storage, networking, DNS, email, logging"
  - "All environments are listed with their purpose and access notes"
  - "Infrastructure source of truth is identified — is it IaC? what technology (e.g. Terraform, Pulumi, CloudFormation)? where does it live in the repo?"
  - "Deployment scripts, CI/CD pipelines, and any other deployment tooling are documented with their locations"
  - "Environment-specific configuration files are identified"
  - "Deployment workflow is described — how changes are previewed, reviewed, and applied"
  - "Recovery and escalation procedures are documented"
  - "Operational references link to the relevant FAQ how-to guides"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

The deployment architecture document describes where and how the system runs — environments, infrastructure, and deployment workflow. Agents (especially SREs and engineers) need this to understand how to access, diagnose, and deploy to each environment.

This depends on T-0002 (architecture overview) since the deployment document builds on an understanding of the system's components.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse infrastructure configuration — IaC modules (Terraform, Pulumi, CloudFormation, etc.), CI/CD pipelines, Dockerfiles, deployment scripts, environment config files — to identify environments, hosting platform, and deployment patterns
   - **If new**: ensure the user has provided sufficient context to describe the deployment architecture. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Review the architecture overview (docs/technical/architecture.md) for component context
3. Write the deployment architecture in `docs/technical/deployment-architecture.md` covering: environments, hosting infrastructure, deployment workflow, and operational references
4. Include diagrams where helpful (Graphviz DOT supported)
5. Remove the TODO placeholder

## Notes

For projects without infrastructure code in the repository, this document may need significant human input about external hosting and deployment processes.
