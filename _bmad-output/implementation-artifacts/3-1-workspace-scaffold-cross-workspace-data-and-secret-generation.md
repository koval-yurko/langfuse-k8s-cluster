# Story 3.1: Workspace Scaffold, Cross-Workspace Data & Secret Generation

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an operator,
I want the app workspace to consume outputs from workspaces 1 and 2 and auto-generate all Langfuse secrets,
so that the Helm deployment has all required configuration without manual secret management.

## Acceptance Criteria

1. **Given** workspaces 1 and 2 have been applied and their outputs are available
   **When** `terraform init && terraform apply` is run in `terraform/03-app/`
   **Then** `providers.tf` configures the TFC backend with workspace name `langfuse-app`, the AWS provider, the Helm provider, and the Kubernetes provider (using EKS cluster endpoint and CA data)

2. `variables.tf` defines `aws_region`, `tfc_organization`, `langfuse_admin_email`, `langfuse_admin_name`, and `langfuse_admin_password`

3. `data.tf` reads workspace 1 outputs (`cluster_name`, `cluster_endpoint`, `cluster_ca_data`) and workspace 2 outputs (`rds_endpoint`, `rds_password`, `s3_bucket_name`, `s3_bucket_region`, `irsa_role_arn`) via `tfe_outputs`

4. `secrets.tf` generates three cryptographically secure random strings (minimum 32 bytes each) for `NEXTAUTH_SECRET`, `SALT`, and `ENCRYPTION_KEY`

## Tasks / Subtasks

- [x] Task 1: Create `providers.tf` — TFC backend + AWS + Helm + Kubernetes providers (AC: 1)
  - [x] 1.1: Configure `terraform.cloud` block with workspace name `langfuse-app`
  - [x] 1.2: Add `required_providers` for `aws` (~>6.0), `tfe` (~>0.62), `random` (~>3.6), `helm` (~>3.1), `kubernetes` (~>2.38)
  - [x] 1.3: Add `provider "aws"` with `region = var.aws_region`
  - [x] 1.4: Add `data "aws_eks_cluster_auth"` to get short-lived token from EKS cluster
  - [x] 1.5: Add `provider "helm"` with kubernetes block using EKS endpoint, CA data, and auth token
  - [x] 1.6: Add `provider "kubernetes"` with EKS endpoint, CA data, and auth token

- [x] Task 2: Create `variables.tf` — input variables for ws3 (AC: 2)
  - [x] 2.1: Add `aws_region` variable (type string, default `us-east-1`)
  - [x] 2.2: Add `tfc_organization` variable (type string, no default)
  - [x] 2.3: Add `langfuse_admin_email` variable (type string, no default)
  - [x] 2.4: Add `langfuse_admin_name` variable (type string, no default)
  - [x] 2.5: Add `langfuse_admin_password` variable (type string, no default, sensitive)

- [x] Task 3: Create `data.tf` — cross-workspace data sources (AC: 3)
  - [x] 3.1: Add `data "tfe_outputs" "network"` reading from `langfuse-network` workspace
  - [x] 3.2: Add `data "tfe_outputs" "deps"` reading from `langfuse-deps` workspace

- [x] Task 4: Create `secrets.tf` — auto-generated Langfuse secrets (AC: 4)
  - [x] 4.1: Add `random_password "nextauth_secret"` (length 32, special = true)
  - [x] 4.2: Add `random_password "salt"` (length 32, special = true)
  - [x] 4.3: Add `random_id "encryption_key"` (byte_length = 32)

- [x] Task 5: Verification (AC: all)
  - [x] 5.1: Validate all `.tf` files are syntactically correct HCL (`terraform fmt -check`)
  - [ ] 5.2: Verify `terraform init -upgrade` fetches all providers successfully — deferred: requires TF_CLOUD_ORGANIZATION env var (structural validation of provider declarations passed)
  - [x] 5.3: Confirm `terraform/03-app/` contains exactly 4 files: `providers.tf`, `variables.tf`, `data.tf`, `secrets.tf`
  - [x] 5.4: Confirm `providers.tf` has exactly 5 required_providers, 1 data source, and 3 provider blocks
  - [x] 5.5: Confirm `variables.tf` has exactly 5 variable blocks
  - [x] 5.6: Confirm `data.tf` has exactly 2 `tfe_outputs` data sources
  - [x] 5.7: Confirm `secrets.tf` has exactly 2 `random_password` resources and 1 `random_id` resource
  - [x] 5.8: Verify no files created outside `terraform/03-app/`

## Dev Notes

### Architecture Compliance

- **File-per-concern pattern**: This story creates the ws3 scaffold — `providers.tf`, `variables.tf`, `data.tf`, `secrets.tf`. Do NOT combine concerns into a single file.
- **No `main.tf`**: The architecture specifies individual concern files. There is no `main.tf` in any workspace.
- **No `outputs.tf` yet**: This story does NOT create `outputs.tf` — ws3 is the terminal workspace and may not need outputs. If needed, Story 3.3 will add it.
- **Naming**: snake_case for all Terraform identifiers. No camelCase, no PascalCase.
- **Comments**: Explain WHY, never WHAT. If the code is self-explanatory, no comment needed.
- **No `locals.tf`**: Keep locals near their usage if needed.
- **No `count` or `for_each`**: Single resources only.
- **Hardcoded values**: Workspace name `langfuse-app`, cluster name references via data sources — all per architecture spec.

### Critical: Provider Configuration Pattern for EKS

The Helm and Kubernetes providers MUST authenticate to the EKS cluster. The standard pattern uses `aws_eks_cluster_auth` data source for a short-lived token:

```hcl
data "aws_eks_cluster_auth" "cluster" {
  name = data.tfe_outputs.network.values.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.tfe_outputs.network.values.cluster_endpoint
    cluster_ca_certificate = base64decode(data.tfe_outputs.network.values.cluster_ca_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = data.tfe_outputs.network.values.cluster_endpoint
  cluster_ca_certificate = base64decode(data.tfe_outputs.network.values.cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
```

**IMPORTANT**: The `data "aws_eks_cluster_auth"` belongs in `providers.tf` (not `data.tf`) because it is a provider configuration dependency — it authenticates the Helm and Kubernetes providers. The `data.tf` file is reserved for cross-workspace `tfe_outputs` data sources. This mirrors how ws1/ws2 keep all provider-related config in `providers.tf`.

### Critical: Cross-Workspace Data Sources

`data.tf` must consume outputs from BOTH upstream workspaces:

```hcl
data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "langfuse-network"
}

data "tfe_outputs" "deps" {
  organization = var.tfc_organization
  workspace    = "langfuse-deps"
}
```

**Available values from network (ws1):**
- `data.tfe_outputs.network.values.vpc_id`
- `data.tfe_outputs.network.values.public_subnet_ids`
- `data.tfe_outputs.network.values.cluster_name`
- `data.tfe_outputs.network.values.cluster_endpoint`
- `data.tfe_outputs.network.values.cluster_ca_data`
- `data.tfe_outputs.network.values.oidc_provider_arn`
- `data.tfe_outputs.network.values.node_security_group_id`

**Available values from deps (ws2):**
- `data.tfe_outputs.deps.values.rds_endpoint`
- `data.tfe_outputs.deps.values.rds_password`
- `data.tfe_outputs.deps.values.s3_bucket_name`
- `data.tfe_outputs.deps.values.s3_bucket_region`
- `data.tfe_outputs.deps.values.irsa_role_arn`

### Critical: Secret Generation Pattern

Per architecture: `random_password` for SALT and NEXTAUTH_SECRET, `random_id` for ENCRYPTION_KEY.

```hcl
resource "random_password" "nextauth_secret" {
  length  = 32
  special = true
}

resource "random_password" "salt" {
  length  = 32
  special = true
}

resource "random_id" "encryption_key" {
  byte_length = 32
}
```

**Why `random_id` for encryption key?** `random_id` produces hex-encoded output (`random_id.encryption_key.hex`) which is pure alphanumeric — required by some encryption routines that don't handle special characters. `random_password` produces human-readable strings with special characters, suitable for NEXTAUTH_SECRET and SALT.

**These resources are consumed in Story 3.2** (Helm values template) via:
- `random_password.nextauth_secret.result`
- `random_password.salt.result`
- `random_id.encryption_key.hex`

### Critical: Provider Version Selection

| Provider | Version | Rationale |
|----------|---------|-----------|
| `hashicorp/aws` | `~> 6.0` | Matches ws1 and ws2 — consistency across workspaces |
| `hashicorp/tfe` | `~> 0.62` | Matches ws1 and ws2 — required for `tfe_outputs` |
| `hashicorp/random` | `~> 3.6` | Matches ws2 — used for secret generation |
| `hashicorp/helm` | `~> 3.1` | Latest stable (3.1.1) — Terraform Plugin Protocol v6 |
| `hashicorp/kubernetes` | `~> 2.38` | Latest stable v2.x — needed for Helm provider k8s auth |

### Critical: Required Terraform Version

Use `required_version = ">= 1.11.1"` to match ws2 convention (ws1 used `>= 1.6` which is less strict). Consistency with the most recent workspace is preferred.

### Critical: Variable Sensitivity

`langfuse_admin_password` MUST be marked `sensitive = true` in the variable block. All other variables are non-sensitive.

### What This Story Creates

This story creates **4 new files** in `terraform/03-app/`:

| File | Purpose | Resources/Blocks |
|------|---------|-----------------|
| `providers.tf` | TFC backend + provider configs | `cloud{}`, 5 `required_providers`, `data "aws_eks_cluster_auth"`, 3 providers (aws, helm, kubernetes) |
| `variables.tf` | Input variables | 5 variables (aws_region, tfc_organization, langfuse_admin_email, langfuse_admin_name, langfuse_admin_password) |
| `data.tf` | Cross-workspace data | 2 `tfe_outputs` data sources (network, deps) |
| `secrets.tf` | Auto-generated secrets | 2 `random_password` + 1 `random_id` |

### What This Story Does NOT Include

- `helm.tf` — Story 3.3 creates this
- `values.yaml.tpl` — Story 3.2 creates this
- `outputs.tf` — ws3 is terminal; may be added later if needed
- Any changes to `terraform/01-network/` or `terraform/02-deps/`
- Kubernetes namespace creation (Helm release handles this via `create_namespace = true`)

### Previous Story (2.3) Intelligence

Story 2.3 completed workspace 2 with these established patterns:
- **Provider block pattern**: `required_version`, `cloud{}` block, `required_providers`, then individual provider configs
- **Data source pattern**: `tfe_outputs` with `organization = var.tfc_organization` and hardcoded workspace name
- **Output naming**: snake_case, descriptive `description` field, `sensitive = true` only when needed
- **File integrity**: Each story adds concern files without modifying unrelated files
- **IAM module v6.x lesson**: Always verify module variable names against latest docs — v5→v6 renamed many inputs/outputs

### Git Intelligence

Recent commit pattern (all 5 implementation stories):
- Each story creates concern files and extends outputs
- Pattern: `story X.Y implementation` commit message
- Files changed are always scoped to the target workspace directory + story/sprint files
- No cross-workspace file modifications

### Project Structure Notes

After this story, `terraform/03-app/` will contain:
```
terraform/03-app/
├── providers.tf     # NEW — TFC backend + AWS/Helm/K8s providers + EKS auth
├── variables.tf     # NEW — 5 input variables
├── data.tf          # NEW — tfe_outputs from ws1 + ws2
└── secrets.tf       # NEW — 3 auto-generated secrets
```

Stories 3.2 and 3.3 will add `values.yaml.tpl` and `helm.tf` to complete the workspace.

### Library/Module Requirements

| Provider/Resource | Version | Purpose |
|-------------------|---------|---------|
| `hashicorp/aws` | ~> 6.0 | AWS provider + `aws_eks_cluster_auth` data source |
| `hashicorp/tfe` | ~> 0.62 | `tfe_outputs` data sources for cross-workspace data |
| `hashicorp/random` | ~> 3.6 | `random_password` and `random_id` for secret generation |
| `hashicorp/helm` | ~> 3.1 | Helm provider for chart deployment (used in Story 3.3) |
| `hashicorp/kubernetes` | ~> 2.38 | Kubernetes provider for cluster access |

**NEW providers to download**: `helm` and `kubernetes` are new to this project. `terraform init` will fetch them and update `.terraform.lock.hcl`.

### Testing Requirements

- `terraform fmt -check` passes on all 4 new files
- `terraform validate` passes (after `terraform init`) — note: requires TFC org env var
- `terraform/03-app/` contains exactly 4 files (no extras)
- `providers.tf` contains: 1 `cloud{}` block, 5 entries in `required_providers`, 1 `data "aws_eks_cluster_auth"`, 3 provider blocks
- `variables.tf` contains exactly 5 `variable` blocks
- `data.tf` contains exactly 2 `data "tfe_outputs"` blocks
- `secrets.tf` contains exactly 2 `random_password` resources and 1 `random_id` resource
- No files created or modified outside `terraform/03-app/`

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries — terraform/03-app/ file list]
- [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Workspace Output Contract — ws1 and ws2 output contracts]
- [Source: _bmad-output/planning-artifacts/architecture.md#Configuration Patterns — Variable Strategy Option C]
- [Source: _bmad-output/planning-artifacts/architecture.md#Core Architectural Decisions — Security Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Implementation Patterns & Consistency Rules]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.1 — acceptance criteria and story statement]
- [Source: _bmad-output/planning-artifacts/prd.md#FR15 — auto-generated Langfuse secrets]
- [Source: _bmad-output/planning-artifacts/prd.md#FR17 — ws1+ws2 outputs consumable by ws3]
- [Source: _bmad-output/planning-artifacts/prd.md#NFR2 — cryptographically secure random generation (minimum 32 bytes)]
- [Source: _bmad-output/implementation-artifacts/2-3-irsa-role-for-s3-access-and-workspace-outputs.md — previous story patterns]
- [Source: terraform/02-deps/providers.tf — provider block pattern reference]
- [Source: terraform/02-deps/data.tf — tfe_outputs pattern reference]
- [Source: terraform/01-network/outputs.tf — ws1 output names (7 outputs)]
- [Source: terraform/02-deps/outputs.tf — ws2 output names (5 outputs)]
- [Source: Terraform Registry — hashicorp/helm provider v3.1.1]
- [Source: Terraform Registry — hashicorp/kubernetes provider v2.38]
- [Source: Terraform Registry — aws_eks_cluster_auth data source]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `terraform init -upgrade` requires `TF_CLOUD_ORGANIZATION` env var — not set in dev session. Structural validation passed; TFC init deferred to operator.

### Completion Notes List

- Created `terraform/03-app/` workspace scaffold with 4 concern files following established ws1/ws2 patterns
- `providers.tf`: TFC backend (langfuse-app), 5 required_providers (aws, tfe, random, helm, kubernetes), `aws_eks_cluster_auth` data source for short-lived EKS token, 3 provider blocks (aws, helm, kubernetes)
- `variables.tf`: 5 input variables including `langfuse_admin_password` with `sensitive = true`
- `data.tf`: 2 `tfe_outputs` data sources consuming ws1 (langfuse-network) and ws2 (langfuse-deps) outputs
- `secrets.tf`: 2 `random_password` resources (nextauth_secret, salt) + 1 `random_id` resource (encryption_key)
- All structural verification checks passed: file counts, resource counts, formatting, no files outside `terraform/03-app/`

### Change Log

- 2026-02-21: Story 3.1 implementation — created ws3 scaffold (providers.tf, variables.tf, data.tf, secrets.tf)
- 2026-02-21: Code review — fixed M1 (override_special on random_password to avoid YAML metacharacters), fixed M2 (unmarked deferred task 5.2), fixed L1 (password validation block)

### File List

- terraform/03-app/providers.tf (new)
- terraform/03-app/variables.tf (new)
- terraform/03-app/data.tf (new)
- terraform/03-app/secrets.tf (new)
