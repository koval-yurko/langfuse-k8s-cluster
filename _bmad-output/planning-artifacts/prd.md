---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-03-success', 'step-04-journeys', 'step-05-domain', 'step-06-innovation', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
inputDocuments:
  - 'research/technical-langfuse-k8s-deployment-research-2026-02-16.md'
workflowType: 'prd'
documentCounts:
  briefs: 0
  research: 1
  brainstorming: 0
  projectDocs: 0
classification:
  projectType: 'developer_tool'
  domain: 'general'
  complexity: 'low'
  projectContext: 'greenfield'
---

# Product Requirements Document - langfuse-k8s-cluster

**Author:** Yura
**Date:** 2026-02-17

## Executive Summary

Self-hosted Langfuse v3 deployment on AWS EKS for personal AI agent tracing, datasets, and evaluations. The project delivers a complete Infrastructure-as-Code solution using a 3-workspace Terraform Cloud architecture (network, dependencies, application) with the official Langfuse Helm chart. External RDS PostgreSQL and S3 provide persistent data that survives cluster teardown, while bundled ClickHouse and Redis handle ephemeral analytics and queuing. Target cost: ~$150/mo, destroyable to zero when idle.

## Success Criteria

### User Success
- Langfuse UI is accessible and functional — traces, datasets, and evals work out of the box
- First trace visible in the UI within minutes of deploying an instrumented AI agent
- No ongoing infrastructure babysitting — the platform runs without intervention

### Business Success
- Monthly cost stays within ~$150 budget
- Time from "git clone" to working Langfuse instance under 1 hour (excluding AWS provisioning wait times)
- Infrastructure fully codified — no manual console clicks, everything reproducible via `terraform apply`

### Technical Success
- All Terraform applies are clean and idempotent
- Langfuse health endpoints return 200 after deployment
- RDS and S3 data survives cluster teardown and rebuild
- IRSA-based S3 access works without static credentials

### Measurable Outcomes
- Langfuse `/api/public/health` returns 200
- At least one trace successfully ingested and visible in UI
- `terraform destroy` + `terraform apply` cycle produces a working instance with data intact (RDS/S3)

## Product Scope

### MVP (Phase 1)

**MVP Approach:** Problem-solving MVP — working self-hosted Langfuse with the smallest possible configuration surface. One user, one environment, one deploy path.

**Core User Journeys Supported:** J1 (First Deployment), J2 (First Trace), J3 (Teardown/Rebuild), J4 (Trace Ingestion) — all four journeys are MVP.

**Must-Have Capabilities:**
- Workspace 1 (Network): VPC + EKS cluster (public subnets, 2x t3.medium, IRSA enabled)
- Workspace 2 (Dependencies): RDS PostgreSQL + S3 bucket + IRSA role + security groups
- Workspace 3 (Application): Helm release with headless init (user/org/project auto-created)
- `.env`-based configuration with `.env.example` template
- Auto-generated secrets (salt, nextauth, encryption key, RDS password)
- Port-forward access to Langfuse UI, ClickHouse, and Redis
- README with deploy, verify, and teardown instructions

### Phase 2 (Growth)
- Ingress controller + Route53 DNS for stable URL
- Spot instances for ~60% compute cost savings
- Terraform Cloud run triggers for cascading applies

### Phase 3 (Expansion)
- Private subnets + NAT gateway
- Managed ClickHouse + ElastiCache Redis
- Secrets Manager via External Secrets Operator
- Monitoring stack (Prometheus/Grafana or CloudWatch)

### Risk Mitigation

| Risk | Likelihood | Mitigation |
|---|---|---|
| EKS ↔ RDS connectivity failure (security groups) | Medium | Research doc provides exact SG config; verify with health endpoint |
| IRSA not picking up S3 credentials | Medium | Verify SA annotation matches IRSA role ARN; test from pod |
| Helm chart version incompatibility | Low | Pin chart version in Terraform; test before changing |
| ClickHouse pods pending (EBS CSI driver) | Medium | Ensure EBS CSI addon enabled on EKS cluster |
| Cost overrun | Low | Public subnets (no NAT), teardown when idle, RDS free tier eligible |

## User Journeys

### Journey 1: Infrastructure Operator — First Deployment

**Yura, Day 1.** He clones the repo, reviews the Terraform code, and runs `terraform apply` on each workspace in sequence — network, deps, app. He waits through the 15-minute EKS provisioning, then the RDS and Helm releases. He runs `kubectl get pods -n langfuse` and sees all pods Running. He port-forwards to localhost:3000, hits the health endpoint — 200. He logs in with the headless-init credentials. The Langfuse dashboard is empty but alive. **The infrastructure works.**

**Capabilities revealed:** Terraform workspace orchestration, health verification, kubectl access, headless authentication

### Journey 2: Langfuse User — First Trace to Eval Loop

**Yura, Day 2.** He opens his AI agent project, adds the Langfuse Python SDK with his project keys, and runs the agent. A trace appears within seconds showing the full call chain. Over the next week he accumulates traces, curates interesting ones into a dataset, and runs his first evaluation. **The "aha!" moment: seeing the agent's reasoning laid out step by step.**

**Capabilities revealed:** SDK connectivity (API keys from headless init), trace ingestion via S3 event pipeline, UI access via port-forward

### Journey 3: Infrastructure Operator — Teardown and Rebuild

**Yura, two weeks later.** He's not using Langfuse this week and wants to save costs. He runs `terraform destroy` on all three workspaces in reverse order. The cluster disappears. RDS and S3 remain. A week later he rebuilds — all his projects, API keys, datasets, and evaluation results are intact. ClickHouse trace history is gone (ephemeral), but raw events in S3 mean nothing critical was lost. **Data persistence works as designed.**

**Capabilities revealed:** Teardown/rebuild cycle, RDS data persistence, S3 data persistence, idempotent Terraform applies

### Journey 4: AI Agent (API Consumer) — Trace Ingestion

**An AI agent in Yura's dev environment** makes an API call. The Langfuse SDK intercepts the call chain and POSTs trace data to the Langfuse Web API at localhost:3000. The Web pod writes raw events to S3, queues a reference in Redis, and the Worker pod picks it up and ingests into ClickHouse. If Langfuse is temporarily down, the SDK silently drops traces with no impact on the agent — observability is non-blocking.

**Capabilities revealed:** S3 event upload (IRSA), Redis queue, ClickHouse ingestion, non-blocking SDK behavior

### Journey Requirements Summary

| Capability | Journeys |
|---|---|
| Terraform 3-workspace orchestration | J1, J3 |
| EKS + managed node group | J1, J3 |
| RDS PostgreSQL (external, persistent) | J1, J2, J3 |
| S3 with IRSA (external, persistent) | J2, J3, J4 |
| Helm chart with headless init | J1, J2 |
| kubectl port-forward access | J1, J2, J3 |
| Langfuse health endpoints | J1, J3 |
| Bundled ClickHouse + Redis | J2, J4 |
| Idempotent deploy/destroy cycle | J3 |

## Developer Tool (IaC) Specific Requirements

### Project-Type Overview

Infrastructure-as-Code project delivering a self-hosted Langfuse v3 instance on AWS EKS. The "product" is a set of Terraform configurations and Helm values that produce a working AI observability platform. Toolchain: Terraform (HCL) + Helm (YAML) + AWS CLI + kubectl.

### Prerequisites & Setup

**Required accounts:**
- AWS account with permissions for EKS, RDS, S3, IAM, VPC, EC2
- Terraform Cloud account (free tier)

**Required local tooling:**
- Terraform CLI >= 1.0
- AWS CLI v2
- kubectl >= 1.27
- Helm >= 3.0 (for debugging only)

**Environment variables (`.env` file, `.env.example` provided, `.env` in `.gitignore`):**

| Variable | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_DEFAULT_REGION` | AWS region (`us-east-1`) |
| `TFE_TOKEN` | Terraform Cloud API token |
| `TFC_ORGANIZATION` | Terraform Cloud org name |
| `LANGFUSE_ADMIN_EMAIL` | Headless init user email |
| `LANGFUSE_ADMIN_NAME` | Headless init user name |
| `LANGFUSE_ADMIN_PASSWORD` | Headless init user password |

No CLI login commands — all auth via environment variables.

### Configuration Surface

**Hardcoded (sensible defaults):**
- AWS region, VPC CIDR, subnet CIDRs
- EKS cluster version (`1.31`), instance type (`t3.medium`), node count (2)
- RDS engine version (`postgres16`), instance class (`db.t4g.micro`)
- Helm chart repository URL, Langfuse namespace (`langfuse`)
- S3 prefixes (`events/`, `media/`, `exports/`)
- ClickHouse and Redis dev passwords

**Auto-generated by Terraform (not user-provided):**
- Langfuse `SALT`, `NEXTAUTH_SECRET`, `ENCRYPTION_KEY` — via `random_password` / `random_id`
- RDS password — via Terraform RDS module

**SDK project keys:** Not pre-configured. Generated via Langfuse UI when needed.

### Implementation Considerations

- `.env.example` with placeholder values included in repo
- `.env` in `.gitignore` — never committed
- README with step-by-step deploy instructions: prerequisites check, TFC workspace setup, apply sequence, verification commands
- Port-forward commands documented for all services:
  - Langfuse UI: `kubectl port-forward svc/langfuse-web -n langfuse 3000:3000`
  - ClickHouse: `kubectl port-forward svc/langfuse-clickhouse -n langfuse 8123:8123`
  - Redis: `kubectl port-forward svc/langfuse-redis-master -n langfuse 6379:6379`
- No Makefile or bootstrap script — raw Terraform commands

## Functional Requirements

### Network Infrastructure Provisioning

- **FR1:** Operator can provision a VPC with public subnets across two availability zones via Terraform
- **FR2:** Operator can provision an EKS cluster with a managed node group (2x t3.medium) in public subnets via Terraform
- **FR3:** EKS cluster provides an OIDC provider for IRSA-based service account authentication
- **FR4:** Operator can access the EKS cluster endpoint publicly for kubectl operations

### Data Storage Provisioning

- **FR5:** Operator can provision an RDS PostgreSQL instance in the same VPC as EKS via Terraform
- **FR6:** RDS is publicly accessible; security group allows port 5432 from EKS nodes and all IPs (`0.0.0.0/0`) for dev access from local machine
- **FR7:** Operator can provision an S3 bucket for Langfuse event, media, and export storage via Terraform
- **FR8:** An IRSA IAM role grants S3 read/write access to Langfuse pods without static credentials
- **FR9:** RDS and S3 persist data independently of EKS cluster lifecycle (survive teardown)

### Application Deployment

- **FR10:** Operator can deploy the Langfuse Helm chart to EKS via Terraform Helm provider
- **FR11:** Helm release configures Langfuse to use external RDS (bundled PostgreSQL disabled)
- **FR12:** Helm release configures Langfuse to use external S3 via IRSA (bundled MinIO disabled)
- **FR13:** Helm release deploys bundled ClickHouse and Redis for in-cluster use
- **FR14:** Helm release performs headless initialization creating a default user, organization, and project
- **FR15:** Langfuse secrets (salt, nextauth secret, encryption key) are auto-generated by Terraform

### Cross-Workspace Orchestration

- **FR16:** Workspace 1 (network) outputs are consumable by Workspace 2 (deps) via `tfe_outputs`
- **FR17:** Workspace 1 and 2 outputs are consumable by Workspace 3 (app) via `tfe_outputs`
- **FR18:** Each workspace can be applied and destroyed independently in the correct sequence

### Service Access

- **FR19:** Operator can access Langfuse UI via kubectl port-forward on port 3000
- **FR20:** Operator can access ClickHouse HTTP interface via kubectl port-forward on port 8123
- **FR21:** Operator can access Redis via kubectl port-forward on port 6379
- **FR22:** Langfuse health endpoint (`/api/public/health`) returns 200 when the system is operational

### Configuration & Environment Management

- **FR23:** All user-provided configuration is defined via a single `.env` file
- **FR24:** A `.env.example` template with placeholder values is included in the repository
- **FR25:** `.env` is excluded from version control via `.gitignore`
- **FR26:** No interactive CLI login commands are required — all authentication is via environment variables

### Lifecycle Management

- **FR27:** Operator can destroy all infrastructure in reverse workspace order via `terraform destroy`
- **FR28:** Operator can rebuild the full stack from scratch and recover all RDS/S3 data
- **FR29:** Terraform applies are idempotent — re-running produces no unintended changes

### Documentation

- **FR30:** README documents prerequisites (accounts, tooling, environment variables)
- **FR31:** README documents the deploy sequence (apply order, wait times, verification commands)
- **FR32:** README documents teardown sequence and data persistence behavior
- **FR33:** README documents port-forward commands for all accessible services

## Non-Functional Requirements

### Security

- **NFR1:** No secrets (AWS keys, TFE token, Langfuse passwords) are committed to version control
- **NFR2:** Auto-generated secrets use cryptographically secure random generation (minimum 32 bytes)
- **NFR3:** RDS is publicly accessible with port 5432 open to all IPs (`0.0.0.0/0`) — dev simplicity, protected by auto-generated password
- **NFR4:** S3 access uses IRSA (short-lived tokens) — no static AWS access keys in pods
- **NFR5:** EKS cluster endpoint is publicly accessible (acceptable for dev; documented trade-off)

### Cost

- **NFR6:** Total monthly infrastructure cost does not exceed ~$155
- **NFR7:** No NAT gateway provisioned (saves ~$32/mo)
- **NFR8:** Infrastructure can be fully destroyed to zero ongoing cost when not in use

### Maintainability

- **NFR9:** Terraform code uses community modules (`terraform-aws-modules/*`) where available
- **NFR10:** Helm chart version is pinned to a specific release
- **NFR11:** Each Terraform workspace is self-contained with clear inputs/outputs
- **NFR12:** Terraform state is managed by Terraform Cloud — no local state files
