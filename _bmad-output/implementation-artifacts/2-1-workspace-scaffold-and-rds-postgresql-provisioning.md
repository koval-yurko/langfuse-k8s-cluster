# Story 2.1: Workspace Scaffold & RDS PostgreSQL Provisioning

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an operator,
I want to provision an RDS PostgreSQL instance in the same VPC as EKS via Terraform Cloud,
so that Langfuse has a persistent relational database that survives cluster teardown.

## Acceptance Criteria

1. **Given** workspace 1 (`langfuse-network`) has been applied and outputs are available
   **When** `terraform init && terraform apply` is run in `terraform/02-deps/`
   **Then** `providers.tf` configures the TFC backend with workspace name `langfuse-deps` and the AWS provider

2. `variables.tf` defines `aws_region` (default `us-east-1`) and `tfc_organization` (no default)

3. `data.tf` reads workspace 1 outputs (`vpc_id`, `public_subnet_ids`, `node_security_group_id`) via `tfe_outputs`

4. `rds.tf` uses `terraform-aws-modules/rds/aws` (~>7.1) to create a PostgreSQL 16 instance (`db.t4g.micro`)

5. RDS is publicly accessible with a security group allowing port 5432 from EKS node SG and `0.0.0.0/0`

6. The database password is auto-generated using `random_password` (32 characters, cryptographically secure)

7. `deletion_protection` is set to `false` for teardown support

8. `outputs.tf` exports `rds_endpoint` and `rds_password` (marked sensitive)

## Tasks / Subtasks

- [x] Task 1: Create `providers.tf` — TFC backend + AWS provider + TFE provider (AC: 1)
  - [x] 1.1: Add `terraform` block with `required_version = ">= 1.11.1"` (required by RDS module v7.x for write-only attributes)
  - [x] 1.2: Add `cloud {}` block with workspace name `langfuse-deps` (organization via `TF_CLOUD_ORGANIZATION` env var — NOT interpolated in `cloud {}` block)
  - [x] 1.3: Add `required_providers` for `aws` (`hashicorp/aws ~> 6.0`), `tfe` (`hashicorp/tfe ~> 0.62`), and `random` (`hashicorp/random ~> 3.6`)
  - [x] 1.4: Add `provider "aws"` block with `region = var.aws_region`

- [x] Task 2: Create `variables.tf` — input variables (AC: 2)
  - [x] 2.1: Add `aws_region` variable (type: string, default: `"us-east-1"`, description: "AWS region for all resources")
  - [x] 2.2: Add `tfc_organization` variable (type: string, no default, description: "Terraform Cloud organization name")

- [x] Task 3: Create `data.tf` — cross-workspace data sources (AC: 3)
  - [x] 3.1: Add `tfe_outputs` data source reading from workspace `langfuse-network` in `var.tfc_organization`
  - [x] 3.2: Extract `vpc_id`, `public_subnet_ids`, and `node_security_group_id` from ws1 outputs (accessed via `data.tfe_outputs.network.values`)

- [x] Task 4: Create `rds.tf` — RDS module + security group + random password (AC: 4, 5, 6, 7)
  - [x] 4.1: Add `random_password` resource for the database password — `length = 32`, `special = true`, `override_special = "!#$%&*()-_=+[]{}<>:?"` (exclude `@/\'"` which break connection strings)
  - [x] 4.2: Add `aws_security_group` resource named `rds` — bare container (no inline rules), VPC from ws1 output
  - [x] 4.3: Add `aws_vpc_security_group_ingress_rule` for EKS node SG — `referenced_security_group_id` from ws1 `node_security_group_id`, port 5432
  - [x] 4.4: Add `aws_vpc_security_group_ingress_rule` for public access — `cidr_ipv4 = "0.0.0.0/0"`, port 5432
  - [x] 4.5: Add `aws_vpc_security_group_egress_rule` for all outbound — `cidr_ipv4 = "0.0.0.0/0"`, `ip_protocol = "-1"`
  - [x] 4.6: Add `module "rds"` using `terraform-aws-modules/rds/aws` version `~> 7.1` with these settings:
    - `identifier = "langfuse-dev"`
    - `engine = "postgres"`, `engine_version = "16"`
    - `instance_class = "db.t4g.micro"`
    - `allocated_storage = 20`
    - `db_name = "langfuse"`
    - `username = "langfuse"`
    - `manage_master_user_password = false` (CRITICAL: defaults to true in v7.x — must disable to use our own password)
    - `password_wo = random_password.db.result` (CRITICAL: v7.x renamed `password` to `password_wo` — write-only attribute)
    - `publicly_accessible = true`
    - `vpc_security_group_ids = [aws_security_group.rds.id]`
    - `create_db_subnet_group = true`, `subnet_ids = data.tfe_outputs.network.values.public_subnet_ids`
    - `deletion_protection = false`
    - `skip_final_snapshot = true`
    - ~~`create_monitoring_iam_role = false`~~ (removed — not supported in RDS module v7.1.0; module defaults to no enhanced monitoring)

- [x] Task 5: Create `outputs.tf` — workspace 2 outputs (AC: 8)
  - [x] 5.1: Add output `rds_endpoint` from `module.rds.db_instance_endpoint`
  - [x] 5.2: Add output `rds_password` from `random_password.db.result` marked `sensitive = true`

- [x] Task 6: Verification (AC: all)
  - [x] 6.1: Validate all files are syntactically correct HCL (`terraform fmt -check`)
  - [x] 6.2: Verify `terraform validate` passes (after `terraform init`)
  - [x] 6.3: Confirm exactly 5 files created: `providers.tf`, `variables.tf`, `data.tf`, `rds.tf`, `outputs.tf`
  - [x] 6.4: Confirm `outputs.tf` exports exactly 2 outputs: `rds_endpoint`, `rds_password`
  - [x] 6.5: Verify no `terraform.tfvars`, `locals.tf`, or `main.tf` files exist

## Dev Notes

### Architecture Compliance

- **File-per-concern pattern**: RDS resources (module, security group, random password) go in `rds.tf`. Do NOT create separate files for security groups or passwords.
- **No `main.tf`**: The architecture specifies `providers.tf`, `data.tf`, `rds.tf`, `s3.tf`, `irsa.tf`, `variables.tf`, `outputs.tf` — there is no `main.tf` in workspace 2.
- **Naming**: snake_case for all Terraform identifiers. No camelCase, no PascalCase.
- **Comments**: Explain WHY, never WHAT. If the code is self-explanatory, no comment needed.
- **No `locals.tf`**: Keep locals near their usage if needed. Do not create a separate locals file.
- **No `terraform.tfvars`**: All variable values come from TFC workspace variables or defaults.
- **No wrapper modules**: Use community modules directly.
- **No `count` or `for_each`**: Single resources only.
- **Output names are a stable API contract**: `rds_endpoint` and `rds_password` form part of the cross-workspace contract consumed by `langfuse-app` (ws3) via `tfe_outputs`. Do NOT rename them.

### Critical: RDS Module v7.x Breaking Changes

The `terraform-aws-modules/rds/aws` module v7.x has critical changes from v6.x:

| Change | Details |
|--------|---------|
| **Password input renamed** | `password` is now `password_wo` (write-only attribute — password is NOT stored in Terraform state) |
| **`manage_master_user_password` defaults to `true`** | Must explicitly set to `false` to use a manually-supplied password via `password_wo` |
| **Terraform version requirement** | `>= 1.11.1` required for write-only attribute support |
| **AWS provider requirement** | `>= 6.27` (our `~> 6.0` constraint resolves this) |

If you use `password` instead of `password_wo`, the module will silently ignore it and AWS Secrets Manager will manage the password instead — breaking the cross-workspace secret sharing.

### Critical: Security Group Pattern (AWS Provider v6.x)

Do NOT use inline `ingress`/`egress` blocks inside `aws_security_group` or the legacy `aws_security_group_rule` resource. Use the modern dedicated resources:

```hcl
# Bare security group (no inline rules)
resource "aws_security_group" "rds" {
  name        = "langfuse-dev-rds"
  description = "Security group for Langfuse RDS instance"
  vpc_id      = data.tfe_outputs.network.values.vpc_id
}

# EKS nodes -> RDS
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = data.tfe_outputs.network.values.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Public access -> RDS (dev convenience)
resource "aws_vpc_security_group_ingress_rule" "rds_from_public" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}
```

### Critical: `cloud {}` Block Does NOT Support Variable Interpolation

The `cloud {}` block in `providers.tf` does NOT support variable references. The organization must come from the `TF_CLOUD_ORGANIZATION` environment variable. This was established in Story 1.1 and must be followed exactly:

```hcl
terraform {
  cloud {
    workspaces {
      name = "langfuse-deps"
    }
  }
}
```

### Critical: `random_password` Special Characters

The `override_special` parameter must exclude characters that break PostgreSQL connection strings: `@`, `/`, `\`, `'`, `"`, backtick. Use:

```hcl
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
```

### Cross-Workspace Data Access Pattern

Workspace 2 reads workspace 1 outputs via `tfe_outputs`:

```hcl
data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "langfuse-network"
}

# Access values:
# data.tfe_outputs.network.values.vpc_id
# data.tfe_outputs.network.values.public_subnet_ids
# data.tfe_outputs.network.values.node_security_group_id
```

### RDS Module Configuration Reference

```hcl
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.1"

  identifier = "langfuse-dev"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  db_name           = "langfuse"
  username          = "langfuse"

  # CRITICAL: v7.x defaults manage_master_user_password to true
  # Must disable to use our own password
  manage_master_user_password = false
  # CRITICAL: v7.x renamed password to password_wo (write-only)
  password_wo = random_password.db.result

  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rds.id]

  create_db_subnet_group = true
  subnet_ids             = data.tfe_outputs.network.values.public_subnet_ids

  deletion_protection = false
  skip_final_snapshot = true

  # No enhanced monitoring for dev
  create_monitoring_iam_role = false
}
```

### What This Story Creates

This story creates the **workspace scaffold** for `terraform/02-deps/` and provisions the RDS PostgreSQL instance. After this story, the directory will contain:

```
terraform/02-deps/
├── providers.tf      # cloud{} backend + AWS + TFE + random providers
├── variables.tf      # aws_region, tfc_organization
├── data.tf           # tfe_outputs from langfuse-network
├── rds.tf            # RDS module + security group + random password
└── outputs.tf        # rds_endpoint, rds_password (sensitive)
```

### What This Story Does NOT Include

- S3 bucket (Story 2.2)
- IRSA role for S3 access (Story 2.3)
- `s3.tf` or `irsa.tf` files
- Any changes to `terraform/01-network/` files
- Any changes to `terraform/03-app/` files

### Outputs After This Story

| Output | Type | Source | Consumer |
|--------|------|--------|----------|
| `rds_endpoint` | string | `module.rds.db_instance_endpoint` | ws3 (Helm values — PostgreSQL host, needs port stripping via `split(":", endpoint)[0]`) |
| `rds_password` | string (sensitive) | `random_password.db.result` | ws3 (Helm values — PostgreSQL auth) |

Note: Stories 2.2 and 2.3 will add `s3_bucket_name`, `s3_bucket_region`, and `irsa_role_arn` to complete the 5-output contract for workspace 2.

### Previous Story (1.2) Intelligence

Story 1.2 established these patterns that MUST be followed in workspace 2:
- **`cloud {}` block**: Does NOT support variable interpolation — organization from `TF_CLOUD_ORGANIZATION` env var
- **TFE provider**: `hashicorp/tfe ~> 0.62` for `tfe_outputs` data sources
- **AWS provider**: Updated to `~> 6.0` (required by EKS module v21.15 and RDS module v7.1)
- **`required_version`**: Was `>= 1.6` in ws1 — bump to `>= 1.11.1` in ws2 for RDS module v7.x write-only support
- **Output naming**: snake_case, descriptive, treated as stable API contract
- **File organization**: One concern per file, snake_case resource names

### Git Intelligence

Recent commits show consistent patterns:
- Story 1.1: Created `providers.tf`, `vpc.tf`, `variables.tf`, `outputs.tf` — file-per-concern pattern
- Story 1.2: Added `eks.tf`, updated `outputs.tf` and `providers.tf` (AWS provider version bump)
- `.gitignore` already includes Terraform patterns (`.terraform/`, `*.tfstate`, `*.tfvars`)

### Library/Module Requirements

| Module | Version | Source | Purpose |
|--------|---------|--------|---------|
| `terraform-aws-modules/rds/aws` | `~> 7.1` | Terraform Registry | RDS PostgreSQL instance |
| `hashicorp/aws` provider | `~> 6.0` | Terraform Registry | AWS resources |
| `hashicorp/tfe` provider | `~> 0.62` | Terraform Registry | Cross-workspace data sharing |
| `hashicorp/random` provider | `~> 3.6` | Terraform Registry | Password generation |

### Testing Requirements

- `terraform fmt -check` passes on all files in `terraform/02-deps/`
- `terraform validate` passes (after `terraform init`)
- Exactly 5 files in `terraform/02-deps/`: `providers.tf`, `variables.tf`, `data.tf`, `rds.tf`, `outputs.tf`
- `outputs.tf` contains exactly 2 output blocks
- No `main.tf`, `locals.tf`, or `terraform.tfvars` files exist
- No local `.tfstate` files exist

### Project Structure Notes

- All 5 files are NEW — workspace 2 directory is being created from scratch
- Aligns with architecture's file-per-concern pattern for `02-deps/`
- `s3.tf` and `irsa.tf` will be added by Stories 2.2 and 2.3 respectively
- No files in `terraform/01-network/` or `terraform/03-app/` should be modified

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Core Architectural Decisions — Data Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Core Architectural Decisions — Security Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Implementation Patterns & Consistency Rules]
- [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Workspace Output Contract]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.1]
- [Source: _bmad-output/planning-artifacts/prd.md#Data Storage Provisioning (FR5-FR9)]
- [Source: _bmad-output/implementation-artifacts/1-2-eks-cluster-addons-and-workspace-outputs.md — Previous story patterns and learnings]
- [Source: terraform-aws-modules/rds/aws v7.x CHANGELOG — password_wo rename, manage_master_user_password default]
- [Source: AWS provider v6.x — aws_vpc_security_group_ingress_rule recommended pattern]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `create_monitoring_iam_role` argument removed from RDS module config — not supported in v7.1.0 (story Dev Notes referenced it but module dropped it)

### Completion Notes List

- Created complete workspace 2 scaffold (`terraform/02-deps/`) with 5 files following file-per-concern pattern from ws1
- `providers.tf`: TFC backend (`langfuse-deps`), AWS/TFE/random providers, `required_version >= 1.11.1` for write-only attribute support
- `variables.tf`: `aws_region` (default `us-east-1`), `tfc_organization` (no default)
- `data.tf`: `tfe_outputs` reading ws1 (`langfuse-network`) for VPC, subnets, and node SG
- `rds.tf`: `random_password` (32 chars), bare `aws_security_group` with dedicated ingress/egress rules, RDS module v7.1 with `password_wo` and `manage_master_user_password = false`
- `outputs.tf`: `rds_endpoint` and `rds_password` (sensitive) as stable cross-workspace API contract
- All acceptance criteria satisfied, `terraform fmt -check` and `terraform validate` pass

### Change Log

- 2026-02-18: Story 2.1 implemented — workspace 2 scaffold and RDS PostgreSQL provisioning (all 6 tasks completed)
- 2026-02-18: Code review — fixed 4 issues: added `description` attributes to 3 SG rules (M3), added `.terraform.lock.hcl` to File List (H1), corrected task 4.6 re: `create_monitoring_iam_role` removal (M2)

### File List

- `terraform/02-deps/providers.tf` (new)
- `terraform/02-deps/variables.tf` (new)
- `terraform/02-deps/data.tf` (new)
- `terraform/02-deps/rds.tf` (new — updated by review: added description attributes to SG rules)
- `terraform/02-deps/outputs.tf` (new)
- `terraform/02-deps/.terraform.lock.hcl` (new — provider lockfile, must be committed)
