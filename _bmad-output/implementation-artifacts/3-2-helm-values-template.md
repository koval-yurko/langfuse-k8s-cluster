# Story 3.2: Helm Values Template

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an operator,
I want a comprehensive Helm values template that configures Langfuse for external RDS, external S3 via IRSA, bundled ClickHouse/Redis, and headless initialization,
so that the Helm chart deploys a correctly wired Langfuse instance.

## Acceptance Criteria

1. **Given** Story 3.1 has been applied and all data sources and secrets are available
   **When** the `values.yaml.tpl` is rendered via `templatefile()`
   **Then** bundled PostgreSQL is disabled and `databaseUrl` points to the external RDS (with port stripped via `split(":", rds_endpoint)[0]`)

2. `shadowDatabaseUrl` is set to empty string and `directUrl` is configured for Prisma migrations

3. Bundled MinIO is disabled and S3 is configured with `bucket`, `region`, `forcePathStyle: false`, and `batchExport.enabled: true`

4. The Langfuse service account is annotated with the IRSA role ARN for S3 access

5. Bundled ClickHouse is enabled with default settings

6. Bundled Redis is enabled with default settings

7. `NEXTAUTH_URL` is set to `http://localhost:3000`

8. `AUTH_DISABLE_SIGNUP` is set to `true`

9. `NEXTAUTH_SECRET`, `SALT`, and `ENCRYPTION_KEY` are injected from generated secrets

10. Headless init env vars (`LANGFUSE_INIT_ORG_ID`, `LANGFUSE_INIT_ORG_NAME`, `LANGFUSE_INIT_PROJECT_NAME`, `LANGFUSE_INIT_USER_EMAIL`, `LANGFUSE_INIT_USER_NAME`, `LANGFUSE_INIT_USER_PASSWORD`) are configured

## Tasks / Subtasks

- [x] Task 1: Create `values.yaml.tpl` in `terraform/03-app/` (AC: all)
  - [x] 1.1: Langfuse core secrets section — `salt`, `nextauth.secret`, `encryptionKey`, `nextauth.url` (AC: 7, 9)
  - [x] 1.2: Service account with IRSA annotation (AC: 4)
  - [x] 1.3: `additionalEnv` — `AUTH_DISABLE_SIGNUP` + all `LANGFUSE_INIT_*` headless init vars (AC: 8, 10)
  - [x] 1.4: PostgreSQL section — `deploy: false`, external RDS host/auth, `directUrl`, `shadowDatabaseUrl` (AC: 1, 2)
  - [x] 1.5: S3 section — `deploy: false`, bucket/region/forcePathStyle, `batchExport.enabled`, event/media prefixes (AC: 3)
  - [x] 1.6: ClickHouse section — `deploy: true`, dev password (AC: 5)
  - [x] 1.7: Redis section — `deploy: true`, dev password (AC: 6)

- [x] Task 2: Verification (AC: all)
  - [x] 2.1: `terraform fmt -check` passes on all files in `terraform/03-app/`
  - [x] 2.2: Validate template renders — confirm all `${variable}` placeholders match variables available in ws3 (data sources + secrets + variables)
  - [x] 2.3: Confirm `terraform/03-app/` now contains exactly 5 files: `providers.tf`, `variables.tf`, `data.tf`, `secrets.tf`, `values.yaml.tpl`
  - [x] 2.4: No files created or modified outside `terraform/03-app/`

## Dev Notes

### Architecture Compliance

- **File location**: `terraform/03-app/values.yaml.tpl` — this is a Helm values template, NOT a `.tf` file
- **Interpolation**: Uses Terraform `templatefile()` syntax — `${variable_name}` placeholders, NOT `{{}}` or HCL expressions
- **File-per-concern**: This file is ONLY the Helm values template. The `helm_release` resource that calls `templatefile()` is created in Story 3.3 (`helm.tf`)
- **No `main.tf`**: Do NOT create a `main.tf`. The architecture specifies individual concern files
- **Naming**: snake_case for all Terraform interpolation variables
- **Comments in YAML**: Explain WHY, never WHAT. Use `#` comments sparingly

### Critical: Helm Chart Key Names (Verified Against Chart v1.5.x)

The Langfuse Helm chart uses specific YAML key names. These are **verified** against the official `values.yaml`:

| Feature | Correct Key | WRONG Key (do NOT use) |
|---------|------------|----------------------|
| Extra env vars | `langfuse.additionalEnv` | ~~`extraEnv`~~, ~~`extraEnvVars`~~ |
| NextAuth URL | `langfuse.nextauth.url` (direct string) | ~~`nextauth.url.value`~~ |
| NextAuth secret | `langfuse.nextauth.secret.value` (nested) | ~~`nextauth.secret`~~ (direct) |
| Salt | `langfuse.salt.value` (nested) | ~~`salt`~~ (direct) |
| Encryption key | `langfuse.encryptionKey.value` (nested) | ~~`encryptionKey`~~ (direct) |
| Signup disabled | `langfuse.features.signUpDisabled` | ~~`AUTH_DISABLE_SIGNUP`~~ (use additionalEnv instead) |
| S3 disable bundled | `s3.deploy: false` | ~~`minio.enabled`~~ |
| PostgreSQL disable | `postgresql.deploy: false` | ~~`postgresql.enabled`~~ |

**IMPORTANT**: `nextauth.url` is a direct string value. `nextauth.secret`, `salt`, and `encryptionKey` use a nested `.value` sub-key. Do NOT mix these patterns.

### Critical: templatefile() Variable Contract

The `values.yaml.tpl` will be called from `helm.tf` (Story 3.3) via:
```hcl
values = [templatefile("values.yaml.tpl", {
  rds_host           = split(":", data.tfe_outputs.deps.values.rds_endpoint)[0]
  rds_password       = data.tfe_outputs.deps.values.rds_password
  s3_bucket          = data.tfe_outputs.deps.values.s3_bucket_name
  s3_region          = data.tfe_outputs.deps.values.s3_bucket_region
  irsa_role_arn      = data.tfe_outputs.deps.values.irsa_role_arn
  nextauth_secret    = random_password.nextauth_secret.result
  salt               = random_password.salt.result
  encryption_key     = random_id.encryption_key.hex
  admin_email        = var.langfuse_admin_email
  admin_name         = var.langfuse_admin_name
  admin_password     = var.langfuse_admin_password
})]
```

**Every `${...}` placeholder in the template MUST match a key in this map.** The template must use EXACTLY these variable names:
- `${rds_host}` — RDS hostname (port already stripped by `split()` in helm.tf)
- `${rds_password}` — RDS auto-generated password
- `${s3_bucket}` — S3 bucket name
- `${s3_region}` — S3 bucket region
- `${irsa_role_arn}` — IRSA role ARN for service account annotation
- `${nextauth_secret}` — auto-generated NextAuth secret
- `${salt}` — auto-generated salt
- `${encryption_key}` — auto-generated encryption key (hex-encoded)
- `${admin_email}` — from `var.langfuse_admin_email`
- `${admin_name}` — from `var.langfuse_admin_name`
- `${admin_password}` — from `var.langfuse_admin_password`

### Critical: RDS Connection String Format

The `directUrl` must be a full Postgres connection string:
```
postgres://langfuse:${rds_password}@${rds_host}:5432/langfuse
```

**Note**: `rds_host` arrives with port already stripped (done in `helm.tf` via `split(":", rds_endpoint)[0]`). The template hardcodes port `5432` in the connection string.

The `shadowDatabaseUrl` must be set to empty string `""` — required by Prisma even if unused.

### Critical: S3 Configuration — No Static Credentials

With IRSA, the S3 section does NOT include `accessKeyId` or `secretAccessKey`. The service account annotation (`eks.amazonaws.com/role-arn`) provides credentials via projected token. Do NOT add any S3 access key fields.

`forcePathStyle: false` is required for native AWS S3 (not MinIO/S3-compatible).

### Critical: additionalEnv for Headless Init

Use `langfuse.additionalEnv` (NOT `extraEnv`) with this exact structure:
```yaml
  additionalEnv:
    - name: AUTH_DISABLE_SIGNUP
      value: "true"
    - name: LANGFUSE_INIT_ORG_ID
      value: "langfuse-dev-org"
```

**Hardcoded values** (per PRD — single user, single environment):
- `LANGFUSE_INIT_ORG_ID`: `"langfuse-dev-org"`
- `LANGFUSE_INIT_ORG_NAME`: `"Dev Org"`
- `LANGFUSE_INIT_PROJECT_ID`: `"langfuse-dev-project"`
- `LANGFUSE_INIT_PROJECT_NAME`: `"langfuse-dev"`

**Interpolated values** (from variables):
- `LANGFUSE_INIT_USER_EMAIL`: `${admin_email}`
- `LANGFUSE_INIT_USER_NAME`: `${admin_name}`
- `LANGFUSE_INIT_USER_PASSWORD`: `${admin_password}`

Headless init is **idempotent** — safe across redeploys, won't duplicate resources.

### Critical: ClickHouse and Redis — Bundled Dev Defaults

Both are `deploy: true` with hardcoded dev passwords:
- ClickHouse: `auth.password: "dev-clickhouse-pw"`
- Redis: `auth.password: "dev-redis-pw"`

These are dev-only — acceptable per architecture doc. No external ClickHouse/Redis (Phase 3).

### What This Story Creates

| File | Purpose |
|------|---------|
| `terraform/03-app/values.yaml.tpl` (new) | Complete Helm values template with `${variable}` placeholders for `templatefile()` interpolation |

### What This Story Does NOT Include

- `helm.tf` — Story 3.3 creates the `helm_release` resource that calls `templatefile()`
- `outputs.tf` — ws3 is terminal; may be added in Story 3.3 if needed
- Any changes to `terraform/01-network/` or `terraform/02-deps/`
- Any changes to existing files in `terraform/03-app/` (providers.tf, variables.tf, data.tf, secrets.tf)

### Expected File Content Structure

The `values.yaml.tpl` should follow this section order:
1. Langfuse core (salt, nextauth, encryptionKey, serviceAccount, features/additionalEnv)
2. PostgreSQL (external RDS)
3. S3 (external, IRSA-based)
4. ClickHouse (bundled)
5. Redis (bundled)

### Previous Story (3.1) Intelligence

- **Provider pattern**: ws3 scaffold established with `providers.tf`, `variables.tf`, `data.tf`, `secrets.tf`
- **Secret references**: `random_password.nextauth_secret.result`, `random_password.salt.result`, `random_id.encryption_key.hex`
- **Data source references**: `data.tfe_outputs.network.values.*`, `data.tfe_outputs.deps.values.*`
- **Code review fix**: `override_special` was added to `random_password` resources to avoid YAML metacharacters — the generated secrets are safe for YAML embedding
- **Variable references**: `var.langfuse_admin_email`, `var.langfuse_admin_name`, `var.langfuse_admin_password`

### Git Intelligence

Recent commits follow pattern `story X.Y implementation`. All changes scoped to target workspace directory + story/sprint files. No cross-workspace modifications.

### Project Structure Notes

After this story, `terraform/03-app/` will contain:
```
terraform/03-app/
├── providers.tf      # Story 3.1 — TFC backend + AWS/Helm/K8s providers
├── variables.tf      # Story 3.1 — 5 input variables
├── data.tf           # Story 3.1 — tfe_outputs from ws1 + ws2
├── secrets.tf        # Story 3.1 — 3 auto-generated secrets
└── values.yaml.tpl   # NEW — Helm values template with ${} interpolation
```

Story 3.3 will add `helm.tf` to complete the workspace.

### Testing Requirements

- `terraform fmt -check` passes on all files in `terraform/03-app/`
- `values.yaml.tpl` contains valid YAML (when placeholders are replaced with sample values)
- Every `${...}` placeholder matches a key in the `templatefile()` variable map
- `terraform/03-app/` contains exactly 5 files (4 existing + 1 new)
- No files created or modified outside `terraform/03-app/`
- No changes to existing files (`providers.tf`, `variables.tf`, `data.tf`, `secrets.tf`)

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Configuration Patterns — Helm Values Strategy (Option A — templatefile)]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries — terraform/03-app/values.yaml.tpl]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.2 — acceptance criteria]
- [Source: _bmad-output/planning-artifacts/prd.md#FR10-FR15 — application deployment requirements]
- [Source: _bmad-output/planning-artifacts/research/technical-langfuse-k8s-deployment-research-2026-02-16.md#Complete Helm values.yaml (Dev)]
- [Source: _bmad-output/implementation-artifacts/3-1-workspace-scaffold-cross-workspace-data-and-secret-generation.md — secret resource names and references]
- [Source: github.com/langfuse/langfuse-k8s values.yaml — verified chart key names: additionalEnv, nextauth.url (string), salt.value, encryptionKey.value]
- [Source: langfuse.com/self-hosting/deployment/kubernetes-helm — Helm chart deployment guide]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

No debug issues encountered.

### Completion Notes List

- Created `terraform/03-app/values.yaml.tpl` with complete Helm values template
- Template follows exact section order: Langfuse core → PostgreSQL → S3 → ClickHouse → Redis
- All 11 `${variable}` placeholders match the `templatefile()` contract from Dev Notes
- Langfuse secrets use correct nested `.value` pattern; `nextauth.url` uses direct string
- Service account annotated with IRSA role ARN for S3 credential injection
- `additionalEnv` includes `AUTH_DISABLE_SIGNUP` + 7 headless init vars (4 hardcoded, 3 interpolated)
- PostgreSQL disabled with external RDS config; includes auth.username/database; `directUrl` uses full connection string; `shadowDatabaseUrl` set to empty
- S3 disabled with external bucket config; includes event/media prefixes; no static credentials (IRSA handles auth); `forcePathStyle: false`
- ClickHouse and Redis bundled with dev passwords
- All verification tasks passed: `terraform fmt -check`, placeholder validation, 5-file count
- **Code Review (2026-02-22):** Fixed missing PostgreSQL auth fields (username, database), added S3 eventUpload/mediaUpload prefixes per research doc and Task 1.5, documented sprint-status.yaml modification

### Change Log

- 2026-02-22: Created `values.yaml.tpl` — complete Helm values template for Langfuse deployment (all ACs satisfied)
- 2026-02-22: **Code Review Fixes** — Added missing PostgreSQL auth fields (username, database), added S3 event/media prefixes, documented sprint-status.yaml change

### File List

- `terraform/03-app/values.yaml.tpl` (new) — Helm values template with `${variable}` placeholders for `templatefile()` interpolation
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified) — Sprint tracking sync (story status updated to "review")
