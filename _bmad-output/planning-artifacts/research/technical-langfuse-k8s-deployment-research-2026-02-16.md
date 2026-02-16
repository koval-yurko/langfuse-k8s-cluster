---
stepsCompleted: [1, 2]
inputDocuments: []
workflowType: 'research'
lastStep: 2
research_type: 'technical'
research_topic: 'Langfuse Helm chart deployment to EKS with external RDS PostgreSQL and S3 persistent storage'
research_goals: 'Practical dev-environment provisioning guide — EKS + RDS + Helm + S3, minimal setup, initial deployment focus'
user_name: 'Yura'
date: '2026-02-16'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical

**Date:** 2026-02-16
**Author:** Yura
**Research Type:** Technical

---

## Research Overview

Technical research into deploying Langfuse v3 on AWS EKS using the official Helm chart, with externally provisioned RDS PostgreSQL and S3 blob storage. Focused on a minimal dev-environment setup managed via Terraform + Terraform Cloud.

---

## Technical Research Scope Confirmation

**Research Topic:** Langfuse Helm chart deployment to EKS with external RDS PostgreSQL and S3 persistent storage
**Research Goals:** Practical dev-environment provisioning guide — EKS + RDS + Helm + S3, minimal setup, initial deployment focus

**Technical Research Scope:**

- Langfuse Helm chart configuration with external services
- External RDS PostgreSQL connection setup
- S3 persistent storage integration (events, media, exports)
- EKS cluster minimal requirements
- Terraform IaC wiring patterns

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-02-16

---

## Technology Stack Analysis

### Langfuse v3 Architecture — Required Components

Langfuse v3 uses a multi-container architecture with dedicated storage backends. All components are required for a functioning deployment:

| Component | Role | Dev Approach |
|-----------|------|--------------|
| **Langfuse Web** | UI + API server | Helm-managed pod |
| **Langfuse Worker** | Async event processing | Helm-managed pod |
| **PostgreSQL** (>= v12) | Transactional data (users, orgs, projects, API keys, settings) | **External RDS** |
| **ClickHouse** | OLAP storage for traces, observations, scores | **Helm-bundled** (dev) |
| **Redis/Valkey** | Queue + cache layer | **Helm-bundled** (dev) |
| **S3 / Blob Storage** | Raw events, multi-modal media, batch exports | **External S3 bucket** |

**Data flow:** API requests hit Langfuse Web, raw events are immediately written to S3, a reference is queued in Redis, then Langfuse Worker picks events from S3 and ingests them into ClickHouse. This design handles request spikes without database bottlenecks.

_Source: [Langfuse Self-Hosting Overview](https://langfuse.com/self-hosting), [Langfuse v3 Stable Release](https://langfuse.com/changelog/2024-12-09-Langfuse-v3-stable-release)_

### Helm Chart — langfuse/langfuse-k8s

The official community-maintained Helm chart is the recommended Kubernetes deployment method.

**Repository:** `https://langfuse.github.io/langfuse-k8s`
**GitHub:** [langfuse/langfuse-k8s](https://github.com/langfuse/langfuse-k8s)
**Current version:** 1.2.x (as of late 2025)
**Chart name:** `langfuse/langfuse`

**Installation:**

```bash
helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update
kubectl create namespace langfuse
helm install langfuse langfuse/langfuse -n langfuse -f values.yaml
```

**Key design decisions in the chart:**
- Chart assumes installation under the release name `langfuse` — different names require adjusting Redis hostname in values.yaml
- Bundled sub-charts for PostgreSQL, ClickHouse, Redis, and MinIO (S3-compatible) via Bitnami
- Each bundled service can be disabled via `deploy: false` to use external services
- Secrets can be provided inline (`value:`) or via Kubernetes secret references (`secretKeyRef:`)

_Source: [Langfuse Helm Docs](https://langfuse.com/self-hosting/deployment/kubernetes-helm), [langfuse-k8s README](https://github.com/langfuse/langfuse-k8s/blob/main/README.md)_

### External PostgreSQL (RDS) Configuration

To use an externally provisioned RDS instance instead of the bundled PostgreSQL:

```yaml
postgresql:
  deploy: false
  auth:
    username: langfuse
    password: "<rds-password>"
    database: langfuse
    host: my-rds-instance.abc123.us-east-1.rds.amazonaws.com
  directUrl: "postgres://langfuse:<password>@<rds-host>:5432/langfuse"
  shadowDatabaseUrl: "postgres://langfuse:<password>@<rds-host>:5432/langfuse"
```

**Key facts:**
- PostgreSQL >= 12 required
- Langfuse expects UTC timezone — RDS default is UTC, so no changes needed
- `directUrl` is used for migrations (can use a user with longer timeouts)
- `shadowDatabaseUrl` is needed if the DB user lacks CREATE DATABASE permissions
- If using `postgres` as the username, use `postgresPassword` instead of `password` in secretKeys
- The `DATABASE_URL` env var is automatically constructed from the Helm values

_Source: [Langfuse PostgreSQL Docs](https://langfuse.com/self-hosting/deployment/infrastructure/postgres), [langfuse-k8s README](https://github.com/langfuse/langfuse-k8s/blob/main/README.md)_

### S3 Blob Storage Configuration

Langfuse uses S3 for three purposes, each configurable independently:

| Use Case | Required? | Env Var Prefix | Description |
|----------|-----------|----------------|-------------|
| **Event Upload** | Mandatory | `LANGFUSE_S3_EVENT_UPLOAD_*` | Raw event data from tracing |
| **Media Upload** | Optional | `LANGFUSE_S3_MEDIA_UPLOAD_*` | Multi-modal assets (images, audio) |
| **Batch Export** | Optional | `LANGFUSE_S3_BATCH_EXPORT_*` | CSV/JSON exports |

**Helm values.yaml for external S3:**

```yaml
s3:
  deploy: false
  bucket: "langfuse-dev-bucket"
  region: "us-east-1"
  endpoint: "https://s3.us-east-1.amazonaws.com"
  forcePathStyle: false
  accessKeyId:
    value: "<access-key>"      # or use secretKeyRef
  secretAccessKey:
    value: "<secret-key>"      # or use secretKeyRef
  eventUpload:
    prefix: "events/"
  mediaUpload:
    prefix: "media/"
  batchExport:
    prefix: "exports/"
```

**Required IAM policy for the S3 bucket:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::langfuse-dev-bucket/*",
        "arn:aws:s3:::langfuse-dev-bucket"
      ]
    }
  ]
}
```

**IRSA alternative (recommended for EKS):** Instead of embedding access keys, use IAM Roles for Service Accounts (IRSA) to grant S3 access to Langfuse pods. This avoids long-lived credentials. The Langfuse S3 SDK will automatically pick up credentials from the pod's projected service account token.

_Source: [Langfuse S3/Blob Storage Docs](https://langfuse.com/self-hosting/deployment/infrastructure/blobstorage), [AWS IRSA Docs](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)_

### Required Secrets

Four secrets must be configured for any Langfuse deployment:

| Secret | Purpose | Generation |
|--------|---------|------------|
| `SALT` | Hashing API keys | Any secure random string |
| `NEXTAUTH_SECRET` | Session cookie validation | Any secure random string |
| `ENCRYPTION_KEY` | Encrypting sensitive data | 256-bit hex: `openssl rand -hex 32` |
| `NEXTAUTH_URL` | Langfuse web URL (for OAuth) | e.g. `http://localhost:3000` for dev |

```yaml
langfuse:
  salt:
    value: "<random-string>"
  nextauth:
    secret:
      value: "<random-string>"
    url:
      value: "http://localhost:3000"
  encryptionKey:
    value: "<64-hex-chars>"
```

_Source: [Langfuse Configuration](https://langfuse.com/self-hosting/configuration)_

### ClickHouse and Redis (Bundled for Dev)

For a minimal dev setup, the Helm chart's bundled ClickHouse and Redis are sufficient — no external provisioning needed:

```yaml
clickhouse:
  deploy: true    # default — uses bundled Bitnami ClickHouse
  auth:
    password: "dev-clickhouse-password"

redis:
  deploy: true    # default — uses bundled Bitnami Redis
  auth:
    password: "dev-redis-password"
```

For production, these would be replaced with Amazon ElastiCache (Redis) and a managed/dedicated ClickHouse instance.

_Source: [Langfuse ClickHouse Docs](https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse), [Langfuse Cache Docs](https://langfuse.com/self-hosting/deployment/infrastructure/cache)_

### Cloud Infrastructure & Deployment Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| **IaC** | Terraform + Terraform Cloud | State management via TFC |
| **Kubernetes** | AWS EKS | Managed control plane |
| **Database** | AWS RDS PostgreSQL | Managed, >= v12 |
| **Object Storage** | AWS S3 | Single bucket with prefixes |
| **Helm** | langfuse/langfuse chart | Deploys all Langfuse components |
| **Container Images** | Bitnami (ClickHouse, Redis) + Langfuse official | Chart uses `bitnamilegacy/*` images as of Aug 2025 |

### Technology Adoption Trends

- **Langfuse v3 is the current stable version** — v2 is legacy. The Helm chart targets v3.
- **ClickHouse adoption** is a major v3 change — enables high-throughput OLAP queries for traces/observations
- **Redis/Valkey as queue** replaces direct DB writes — decouples ingestion from storage
- **S3 as event source of truth** is a reliability pattern — events survive even if ClickHouse is temporarily down
- **IRSA is the preferred credential model** for EKS workloads accessing AWS services — avoids static access keys
- **Bitnami registry restructure (Aug 2025)** — chart updated to use `bitnamilegacy/*` images to prevent pull failures

_Source: [Langfuse v3 Release Notes](https://langfuse.com/changelog/2024-12-09-Langfuse-v3-stable-release), [langfuse-k8s Releases](https://github.com/langfuse/langfuse-k8s/releases)_
