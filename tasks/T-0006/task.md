---
id: T-0006
title: "Write how to access deployment environments"
type: task
status: todo
priority: P1
owner: null
labels:
  - setup
  - docs
depends_on:
  - T-0003
  - T-0005
parallel_with: []
parent_epic: E-0001
acceptance:
  - "docs/faq/how-to-access-deployment-environments.md documents how to access each remote environment"
  - "Prerequisites for remote access are listed (e.g. CLI tools, credentials, VPN, SSO profiles)"
  - "How to check for an active session or valid credentials is documented"
  - "How to authenticate for remote access is documented (including when a human is required)"
  - "How to view application logs remotely is referenced or covered"
  - "How to access databases remotely is documented (if applicable)"
  - "How to check service health is documented (if applicable)"
  - "Environment reference table is included (URLs, log locations, database access)"
  - "Troubleshooting common access failures is included"
  - "The agent has exercised the documented instructions and confirmed they work"
  - "The TODO placeholder is replaced with meaningful content"
created_at: '2026-03-20'
updated_at: '2026-03-20'
---

## Context

Agents — especially SREs, testers, and engineers — need to access remote environments for diagnosis, verification, and deployment. This guide covers the prerequisites, authentication, and common operations for each hosted environment.

Depends on T-0003 (deployment architecture) which identifies the environments, and T-0005 (login) which covers application-level authentication.

## Plan

1. Determine whether this is a new or existing project by analysing the repository
   - **If existing**: analyse deployment scripts, CI/CD configuration, cloud provider tooling, and any existing access documentation to identify how remote environments are accessed
   - **If new**: ensure the user has provided sufficient context to describe remote environment access. If not, ask for help — see [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md)
2. Review the deployment architecture document (docs/technical/deployment-architecture.md) for environment details
3. Identify prerequisites: CLI tools, cloud provider credentials, VPN, SSO profiles, etc.
4. Document how to check for valid access, how to authenticate, and when a human is needed
5. Document common operations: viewing logs, accessing databases, checking service health
6. Include an environment reference table and troubleshooting section
7. Follow the documented instructions end-to-end and confirm each step works
8. Fix any inaccuracies found during verification
9. Remove the TODO placeholder

## Notes

This task is most likely to require significant human input. Many teams have not considered how agents should access deployment environments, and the necessary tooling, credentials, or access patterns may not exist yet. The agent should identify gaps early and escalate to humans rather than guessing.

Some remote access steps (e.g. SSO browser flows, VPN connections) cannot be completed by agents and will require human involvement. The guide should clearly identify these steps and reference [How to ask humans to do something](/docs/faq/how-to-ask-humans-to-do-something.md).
