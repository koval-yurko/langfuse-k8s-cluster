# Story 1.2: EKS Cluster, Addons & Workspace Outputs

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an operator,
I want to provision an EKS cluster with a managed node group, OIDC provider, and EBS CSI Driver in the VPC,
so that I have a Kubernetes platform ready for workloads and persistent volume support.

## Acceptance Criteria

1. **Given** Story 1.1 has been applied and the VPC exists
   **When** `terraform apply` is run in `terraform/01-network/`
   **Then** an EKS cluster (version 1.35) is created using `terraform-aws-modules/eks/aws` (~>21.15) in the public subnets

2. A managed node group with 2x `t3.medium` instances is provisioned

3. The cluster endpoint is publicly accessible

4. An OIDC provider is enabled for IRSA-based service account authentication

5. The EBS CSI Driver addon is installed with a dedicated IRSA role (required for ClickHouse PVC)

6. `outputs.tf` exports all 7 workspace outputs: `vpc_id`, `public_subnet_ids`, `cluster_name`, `cluster_endpoint`, `cluster_ca_data`, `oidc_provider_arn`, `node_security_group_id`

7. These outputs are consumable by workspace 2 (`langfuse-deps`) via `tfe_outputs`

## Tasks / Subtasks

- [x] Task 1: Create `eks.tf` — EKS module + EBS CSI Driver addon + EBS CSI IRSA (AC: 1, 2, 3, 4, 5)
  - [x] 1.1: Add `module "eks"` using `terraform-aws-modules/eks/aws` version `~> 21.15`
  - [x] 1.2: Set cluster `name` to `"langfuse-dev"`, `kubernetes_version` to `"1.35"` (NOTE: v21.x renamed `cluster_name` → `name`, `cluster_version` → `kubernetes_version`)
  - [x] 1.3: Set `vpc_id = module.vpc.vpc_id` and `subnet_ids = module.vpc.public_subnets`
  - [x] 1.4: Set `endpoint_public_access = true` (NOTE: v21.x renamed `cluster_endpoint_public_access` → `endpoint_public_access`)
  - [x] 1.5: Configure `eks_managed_node_groups` with a `default` group: `instance_types = ["t3.medium"]`, `min_size = 2`, `max_size = 2`, `desired_size = 2`
  - [x] 1.6: Add `addons` block (NOTE: v21.x renamed `cluster_addons` → `addons`) with `aws-ebs-csi-driver` addon using `most_recent = true` and `service_account_role_arn = module.ebs_csi_irsa.arn`
  - [x] 1.7: Add `module "ebs_csi_irsa"` using `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts` version `~> 6.4`
  - [x] 1.8: Configure EBS CSI IRSA with `attach_ebs_csi_policy = true`, `name = "langfuse-dev-ebs-csi"`, and OIDC provider from `module.eks.oidc_provider_arn` targeting `kube-system:ebs-csi-controller-sa`

- [x] Task 2: Update `outputs.tf` — add 5 EKS outputs (AC: 6, 7)
  - [x] 2.1: Add output `cluster_name` from `module.eks.cluster_name`
  - [x] 2.2: Add output `cluster_endpoint` from `module.eks.cluster_endpoint`
  - [x] 2.3: Add output `cluster_ca_data` from `module.eks.cluster_certificate_authority_data`
  - [x] 2.4: Add output `oidc_provider_arn` from `module.eks.oidc_provider_arn`
  - [x] 2.5: Add output `node_security_group_id` from `module.eks.node_security_group_id`

- [x] Task 3: Update `providers.tf` — add IAM provider if needed (AC: 5)
  - [x] 3.1: Verify AWS provider version constraint `~> 5.0` is compatible with EKS module ~>21.15. If EKS module requires AWS provider >= 6.0, update to `~> 6.0` and document the change.

- [x] Task 4: Verification (AC: all)
  - [x] 4.1: Validate all files are syntactically correct HCL (`terraform fmt -check`)
  - [x] 4.2: Verify `terraform validate` passes (after `terraform init`)
  - [x] 4.3: Confirm `outputs.tf` exports exactly 7 outputs (2 from Story 1.1 + 5 new)
  - [x] 4.4: Confirm no new files beyond `eks.tf` are created (all changes are in existing files or the one new `eks.tf`)
  - [x] 4.5: Verify output names match the cross-workspace contract exactly: `vpc_id`, `public_subnet_ids`, `cluster_name`, `cluster_endpoint`, `cluster_ca_data`, `oidc_provider_arn`, `node_security_group_id`

## Dev Notes

### Architecture Compliance

- **File-per-concern pattern**: EKS resources (module, addon, EBS CSI IRSA) go in `eks.tf`. Do NOT put them in `vpc.tf` or create a `main.tf`.
- **No `main.tf`**: The architecture specifies `providers.tf`, `vpc.tf`, `eks.tf`, `variables.tf`, `outputs.tf` — there is no `main.tf` in workspace 1.
- **Naming**: snake_case for all Terraform identifiers. No camelCase, no PascalCase.
- **Comments**: Explain WHY, never WHAT. If the code is self-explanatory, no comment needed.
- **No `locals.tf`**: Keep locals near their usage if needed. Do not create a separate locals file.
- **No `terraform.tfvars`**: All variable values come from TFC workspace variables or defaults.
- **No wrapper modules**: Use community modules directly — do not wrap them in local modules.
- **No `count` or `for_each`**: Single resources only in this project.
- **Output names are a stable API contract**: These 7 outputs form the cross-workspace contract consumed by `langfuse-deps` (ws2) and `langfuse-app` (ws3) via `tfe_outputs`. Do NOT rename them.

### Critical: EKS Module v21.x Input Variable Renames

The `terraform-aws-modules/eks/aws` module v21.x renamed several input variables from v20.x. **You MUST use the v21.x names:**

| v20.x (OLD — DO NOT USE) | v21.x (CORRECT) |
|---|---|
| `cluster_name` | `name` |
| `cluster_version` | `kubernetes_version` |
| `cluster_addons` | `addons` |
| `cluster_endpoint_public_access` | `endpoint_public_access` |

**Output names are UNCHANGED** — `module.eks.cluster_name`, `module.eks.cluster_endpoint`, etc. remain valid.

### Critical: AWS Provider Version Compatibility

The architecture specifies AWS provider `~> 5.0` in `providers.tf`. EKS module v21.x may require AWS provider `>= 6.0`. **Check the module's `required_providers` block during `terraform init`.** If there's a conflict:
- Update `providers.tf` to `~> 6.0`
- This affects Story 1.1's existing `providers.tf` — document the change

### EBS CSI Driver — Why and How

**Why**: ClickHouse (deployed via Helm in workspace 3) uses EBS-backed PersistentVolumeClaims. Without the EBS CSI driver, ClickHouse pods will be stuck in `Pending` state.

**How**: The EKS module's `addons` block supports installing EKS-managed addons. The EBS CSI driver needs IAM permissions to manage EBS volumes, provided via IRSA:

```hcl
# In eks.tf — EBS CSI IRSA role
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4"

  name                  = "langfuse-dev-ebs-csi"
  attach_ebs_csi_policy = true  # Attaches AmazonEBSCSIDriverPolicy automatically

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
```

The `attach_ebs_csi_policy = true` parameter in the IAM IRSA module automatically attaches the AWS-managed `AmazonEBSCSIDriverPolicy` — no custom policy needed.

> **Note:** IAM IRSA module v6.4 renamed the submodule from `iam-role-for-service-accounts-eks` to `iam-role-for-service-accounts`, input `role_name` to `name`, and output `iam_role_arn` to `arn`.

### EKS Module Configuration Reference

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = "langfuse-dev"
  kubernetes_version = "1.35"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  endpoint_public_access = true

  # IRSA defaults to true in v21.x — OIDC provider created automatically
  # enable_irsa = true  # not needed, default is true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 2
      desired_size   = 2
    }
  }

  # EBS CSI Driver addon — required for ClickHouse PVC
  addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }
}
```

### IRSA — Enabled by Default

In EKS module v21.x, `enable_irsa` defaults to `true`. This means the OIDC provider is created automatically. You do NOT need to set `enable_irsa = true` explicitly. The `module.eks.oidc_provider_arn` output will be available for downstream consumers (ws2 IRSA role for S3 access).

### Node Group — Why Fixed Size 2

Two `t3.medium` nodes (2 vCPU, 4 GiB each → 4 vCPU, 8 GiB total) provide enough capacity for:
- Langfuse Web + Worker pods (~0.5 CPU, ~1 GiB each)
- ClickHouse (~1 CPU, ~2 GiB)
- Redis (~0.25 CPU, ~256 MiB)
- System pods (CoreDNS, kube-proxy, etc.)

Setting `max_size = 2` prevents accidental scaling. For dev, fixed size is intentional.

### Cross-Workspace Output Contract

After this story, `outputs.tf` exposes the complete contract for downstream workspaces:

| Output | Type | Consumer |
|--------|------|----------|
| `vpc_id` | string | ws2 (RDS subnet group, security group) |
| `public_subnet_ids` | list(string) | ws2 (RDS subnet group) |
| `cluster_name` | string | ws3 (Helm/K8s provider auth) |
| `cluster_endpoint` | string | ws3 (Helm/K8s provider) |
| `cluster_ca_data` | string | ws3 (Helm/K8s provider) |
| `oidc_provider_arn` | string | ws2 (IRSA role trust policy) |
| `node_security_group_id` | string | ws2 (RDS security group ingress) |

### Previous Story (1.1) Intelligence

Story 1.1 established key patterns that MUST be followed:
- **`cloud {}` block**: Does NOT support variable interpolation — organization comes from `TF_CLOUD_ORGANIZATION` env var
- **TFE provider**: Already declared in `providers.tf` (`hashicorp/tfe ~> 0.62`) for `tfe_outputs` data sources
- **`required_version`**: Set to `>= 1.6` — keep or update if needed
- **VPC module outputs**: `module.vpc.vpc_id` and `module.vpc.public_subnets` are the references to use in `eks.tf`
- **Subnet tags**: Story 1.1 already added `"kubernetes.io/role/elb" = 1` tag to public subnets for EKS LB discovery

### What This Story Does NOT Include

- RDS PostgreSQL (Epic 2, Story 2.1)
- S3 bucket (Epic 2, Story 2.2)
- Langfuse S3 IRSA role (Epic 2, Story 2.3)
- Helm release (Epic 3)
- Any files in `terraform/02-deps/` or `terraform/03-app/`
- No changes to `vpc.tf` or `variables.tf`

### Project Structure After This Story

```
langfuse-k8s-cluster/
└── terraform/
    └── 01-network/
        ├── providers.tf      # cloud{} backend + AWS provider (may need version bump)
        ├── vpc.tf            # VPC module (unchanged from Story 1.1)
        ├── eks.tf            # NEW: EKS module + EBS CSI addon + EBS CSI IRSA
        ├── variables.tf      # aws_region, tfc_organization (unchanged from Story 1.1)
        └── outputs.tf        # MODIFIED: 7 outputs (2 VPC + 5 EKS)
```

### Library/Module Requirements

| Module | Version | Source | Purpose |
|--------|---------|--------|---------|
| `terraform-aws-modules/eks/aws` | `~> 21.15` | Terraform Registry | EKS cluster + managed node group + addons |
| `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks` | `~> 6.4` | Terraform Registry | EBS CSI Driver IRSA role |
| `hashicorp/aws` provider | `~> 5.0` (or `~> 6.0` if required by EKS module) | Terraform Registry | AWS resources |

### Testing Requirements

- `terraform fmt -check` passes on all files (including new `eks.tf`)
- `terraform validate` passes (may require `terraform init` first to download EKS and IAM modules)
- `outputs.tf` contains exactly 7 output blocks
- `eks.tf` is the only new file created
- `outputs.tf` is the only existing file modified (adding 5 outputs)
- No local `.tfstate` files exist

### Project Structure Notes

- `eks.tf` is a NEW file — aligns with architecture's file-per-concern pattern
- `outputs.tf` is MODIFIED — adds 5 EKS outputs to existing 2 VPC outputs
- `providers.tf` may need modification if AWS provider version bump is required
- No other files in `terraform/01-network/` should be modified

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Core Architectural Decisions — Infrastructure Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Implementation Patterns & Consistency Rules]
- [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Workspace Output Contract]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries]
- [Source: _bmad-output/planning-artifacts/research/technical-langfuse-k8s-deployment-research-2026-02-16.md#Workspace 1: Network — VPC + EKS]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2]
- [Source: _bmad-output/implementation-artifacts/1-1-terraform-workspace-scaffold-and-vpc-provisioning.md — Previous story patterns and learnings]
- [Source: terraform-aws-modules/eks/aws v21.x UPGRADE-21.0.md — Variable renames]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- IAM IRSA module v6.4 renamed submodule path from `iam-role-for-service-accounts-eks` to `iam-role-for-service-accounts` — fixed during `terraform init`
- IAM IRSA module v6.4 renamed input `role_name` to `name` and output `iam_role_arn` to `arn` — fixed during `terraform validate`
- AWS provider updated from `~> 5.0` to `~> 6.0` as EKS module v21.15 requires `>= 6.28`

### Completion Notes List

- Created `eks.tf` with EKS cluster module (v21.15) using correct v21.x input variable names (`name`, `kubernetes_version`, `endpoint_public_access`, `addons`)
- Configured managed node group with 2x t3.medium fixed-size instances
- Installed EBS CSI Driver addon via EKS addons block with IRSA role for IAM permissions
- Added 5 EKS outputs to `outputs.tf` (total 7 outputs matching cross-workspace contract)
- Updated AWS provider from `~> 5.0` to `~> 6.0` in `providers.tf` (required by EKS module v21.15)
- All verification passed: `terraform fmt -check`, `terraform validate`, 7 outputs confirmed, output names match contract

### File List

- `terraform/01-network/eks.tf` (NEW) — EKS cluster module + EBS CSI Driver addon + EBS CSI IRSA role
- `terraform/01-network/outputs.tf` (MODIFIED) — Added 5 EKS outputs (cluster_name, cluster_endpoint, cluster_ca_data, oidc_provider_arn, node_security_group_id)
- `terraform/01-network/providers.tf` (MODIFIED) — Updated AWS provider version from `~> 5.0` to `~> 6.0`
- `terraform/01-network/.terraform.lock.hcl` (NEW) — Auto-generated provider lock file from `terraform init`
- `.gitignore` (MODIFIED) — Added Terraform-specific ignore patterns (.terraform/, *.tfstate, *.tfvars, etc.)

## Change Log

- 2026-02-17: Story 1.2 implemented — EKS cluster, EBS CSI Driver addon, IRSA role, 5 new outputs, AWS provider version bump to ~> 6.0
- 2026-02-17: Code review — Fixed 4 MEDIUM issues: added .gitignore and .terraform.lock.hcl to File List, generated cross-platform lock file hashes, updated stale IRSA code examples in Dev Notes
