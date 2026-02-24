# Langfuse Kubernetes Cluster on AWS

This repository provides Infrastructure-as-Code (Terraform + Helm) to deploy a fully-functional [Langfuse](https://langfuse.com) instance on AWS EKS with persistent external storage (RDS PostgreSQL + S3).

## Architecture Overview

The deployment is organized into **3 independent Terraform workspaces**:

1. **`01-network`** — VPC and EKS cluster (workspace: `langfuse-network`)
2. **`02-deps`** — RDS PostgreSQL, S3, and IRSA roles (workspace: `langfuse-deps`)
3. **`03-app`** — Langfuse Helm chart deployment (workspace: `langfuse-app`)

**Key Features:**
- External RDS PostgreSQL for persistent data storage
- S3 bucket for event/media/export storage with IRSA authentication
- Bundled ClickHouse and Redis (ephemeral, in-cluster)
- Auto-generated secrets (no manual secret management)
- Headless initialization (default user, org, and project created automatically)
- Independent workspace lifecycle (destroy/rebuild support)
- ~$155/month infrastructure cost (destroyable to zero when not in use)

## Prerequisites

### Required Accounts

1. **AWS Account** with programmatic access (access key and secret key)
2. **Terraform Cloud Account** (free tier) — [Sign up here](https://app.terraform.io/signup)

### Required Tools

Install the following tools on your local machine:

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| [Terraform](https://www.terraform.io/downloads) | 1.9+ | `brew install terraform` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.28+ | `brew install kubectl` |
| [AWS CLI](https://aws.amazon.com/cli/) | 2.x | `brew install awscli` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | `brew install helm` |

### Terraform Cloud Setup

1. Create a free account at [Terraform Cloud](https://app.terraform.io/signup)
2. Create an organization (or use an existing one)
3. Generate a **User API Token**:
   - Go to **User Settings** → **Tokens**
   - Click **Create an API token**
   - Save the token (you'll need it for `.env`)

**Note:** You do NOT need to manually create workspaces — Terraform will create them automatically on first apply.

4. Configure **Remote state sharing** so downstream workspaces can read outputs from upstream ones:
   - **`langfuse-network`** → Settings → General → Remote state sharing → share with `langfuse-deps` and `langfuse-app`
   - **`langfuse-deps`** → Settings → General → Remote state sharing → share with `langfuse-app`

   Alternatively, select "Share with all workspaces in this organization" on both.

   > Without this, `tfe_outputs` data sources in downstream workspaces will return empty `nonsensitive_values`.

## Configuration

### 1. Copy the Environment Template

```bash
cp .env.example .env
```

### 2. Configure Your `.env` File

Edit `.env` and fill in all required values:

```bash
# AWS Credentials
export AWS_ACCESS_KEY_ID=your-aws-access-key
export AWS_SECRET_ACCESS_KEY=your-aws-secret-key
export AWS_DEFAULT_REGION=eu-central-1

# Terraform Cloud
export TF_CLOUD_ORGANIZATION=your-tfc-organization-name
export TF_VAR_tfc_organization=$TF_CLOUD_ORGANIZATION
export TFC_TOKEN=your-terraform-cloud-api-token

# Langfuse Admin User (created during headless init)
export TF_VAR_langfuse_admin_email=admin@example.com
export TF_VAR_langfuse_admin_name="Admin User"
export TF_VAR_langfuse_admin_password=your-secure-password
```

**Important:**
- Never commit `.env` to version control (it's already in `.gitignore`)
- All authentication is via environment variables — no interactive CLI logins required

### 3. Load Environment Variables

Before running any Terraform commands, you must export the environment variables. There are two methods:

**Method 1: Source the .env file (Recommended)**

```bash
source .env
```

**Method 2: Copy/paste export commands directly**

Open `.env` in your editor, select all the `export` commands, and paste them directly into your terminal. This is useful if `source` doesn't work in your shell or if you want to verify each variable as it's set.

**Verify variables are loaded:**

```bash
echo $TF_CLOUD_ORGANIZATION
echo $AWS_ACCESS_KEY_ID
```

Both should return the values you configured (not empty).

**Important:** Environment variables only persist in the current terminal session. If you open a new terminal window, you must re-run `source .env` or re-paste the export commands.

## Deployment

### Deploy Sequence

**IMPORTANT:** Workspaces must be applied in order due to cross-workspace dependencies.

#### Step 1: Configure Remote State Sharing

After the first `terraform apply` in `01-network` creates the workspaces, configure remote state sharing in Terraform Cloud so downstream workspaces can read outputs:

1. **`langfuse-network`** → Settings → General → Remote state sharing → share with `langfuse-deps` and `langfuse-app`
2. **`langfuse-deps`** → Settings → General → Remote state sharing → share with `langfuse-app`

Alternatively, select "Share with all workspaces in this organization" on both.

> Without this, `tfe_outputs` data sources will return empty `nonsensitive_values` and plans will fail.

#### Step 2: Deploy Network Infrastructure (Workspace 1)

```bash
cd terraform/01-network
terraform init
terraform apply
```

**What this creates:**
- VPC with public subnets across 2 availability zones
- EKS cluster (Kubernetes 1.32) with 2x t2.medium nodes
- EBS CSI Driver addon (required for ClickHouse persistent volumes)
- OIDC provider for IRSA authentication

**Expected time:** ~15-20 minutes

**Verification:**
```bash
# Configure kubectl
aws eks update-kubeconfig --name langfuse-dev --region eu-central-1

# Verify nodes are ready
kubectl get nodes
```

#### Step 3: Deploy Persistent Data Layer (Workspace 2)

```bash
cd ../02-deps
terraform init
terraform apply
```

**What this creates:**
- RDS PostgreSQL 16 instance (db.t4g.micro)
- S3 bucket for Langfuse storage
- IRSA IAM role granting Langfuse pods S3 access

**Expected time:** ~10-15 minutes

**Note:** RDS and S3 resources persist independently of the EKS cluster lifecycle.

#### Step 4: Deploy Langfuse Application (Workspace 3)

```bash
cd ../03-app
terraform init
terraform apply
```

**What this creates:**
- Langfuse Helm release (web + worker pods)
- Bundled ClickHouse (analytics database)
- Bundled Redis (queue + cache)
- Auto-generated secrets (salt, nextauth, encryption key)
- Default organization, project, and admin user

**Expected time:** ~5-10 minutes

**Wait for pods to be ready:**
```bash
kubectl get pods -n langfuse -w
```

All pods should reach `Running` status. The `langfuse-web` pod may restart once during initialization — this is normal.

## Verification

### 1. Check Health Endpoint

```bash
# Port-forward the Langfuse web service
kubectl port-forward -n langfuse svc/langfuse-web 3000:3000
```

In another terminal:

```bash
curl http://localhost:3000/api/public/health
```

**Expected response:** HTTP 200 with JSON indicating the system is operational.

### 2. Access Langfuse UI

With the port-forward still active, open your browser:

```
http://localhost:3000
```

**Login credentials:**
- Email: The value from `TF_VAR_langfuse_admin_email` in your `.env`
- Password: The value from `TF_VAR_langfuse_admin_password` in your `.env`

You should see a pre-initialized organization and project ready to use.

## Service Access

All services are accessed via `kubectl port-forward` (no public ingress configured).

### Langfuse Web UI

```bash
kubectl port-forward -n langfuse svc/langfuse-web 3000:3000
```

Access at: `http://localhost:3000`

### ClickHouse HTTP Interface

```bash
kubectl port-forward -n langfuse svc/langfuse-clickhouse 8123:8123
```

Access at: `http://localhost:8123` (default user: `default`, password: `clickhouse`)

### Redis CLI

```bash
kubectl port-forward -n langfuse svc/langfuse-redis-master 6379:6379
```

Connect with:

```bash
redis-cli -h localhost -p 6379
```

### PostgreSQL (RDS)

The RDS instance is publicly accessible for dev convenience.

Get the endpoint:

```bash
cd terraform/02-deps
terraform output rds_endpoint
```

Connect with:

```bash
psql -h <rds-endpoint> -U langfuse -d langfuse
# Password: auto-generated (retrieve with `terraform output rds_password`)
```

## Teardown

### Destroy Sequence

**IMPORTANT:** Destroy workspaces in **reverse order** to respect dependencies.

#### Step 1: Destroy Application Layer

```bash
cd terraform/03-app
terraform destroy
```

This removes the Helm release and all in-cluster resources (ClickHouse, Redis, pods). **RDS and S3 data remain intact.**

#### Step 2: Destroy Data Layer (Optional)

```bash
cd ../02-deps
terraform destroy
```

**WARNING:** This destroys RDS and S3 resources. **All Langfuse data will be permanently deleted.**

If you want to preserve data for future rebuilds, **skip this step**.

#### Step 3: Destroy Network Infrastructure

```bash
cd ../01-network
terraform destroy
```

This removes the EKS cluster and VPC. **Expected time:** ~15-20 minutes.

### Data Persistence Behavior

| Workspace | Resources | Lifecycle |
|-----------|-----------|-----------|
| `03-app` | ClickHouse, Redis, Langfuse pods | **Ephemeral** — destroyed with workspace 3 |
| `02-deps` | RDS, S3 | **Persistent** — survive cluster teardown |
| `01-network` | VPC, EKS | **Foundational** — destroyed last |

**Cost Optimization:**
- Destroy workspace 3 when not in use → saves EKS node costs (~$60/mo)
- Keep workspace 2 intact → preserves all data, costs ~$15/mo (RDS) + ~$1/mo (S3)
- Destroy all workspaces → zero ongoing cost

## Rebuild from Scratch

### Full Rebuild (with Data Recovery)

If you destroyed only workspace 3 (or workspaces 3 + 1), you can rebuild the full stack:

```bash
# 1. Re-apply network (if destroyed)
cd terraform/01-network
terraform apply

# 2. Re-apply deps (if destroyed, or if you want to create new RDS/S3)
cd ../02-deps
terraform apply

# 3. Re-apply app
cd ../03-app
terraform apply
```

**Data recovery:**
- If workspace 2 was never destroyed, the new Langfuse deployment automatically reconnects to the existing RDS database and S3 bucket
- All previous data (traces, prompts, users, projects) is immediately available

### Fresh Start (Clean Data)

To start with a completely clean slate:

```bash
# Destroy everything (including data)
cd terraform/03-app && terraform destroy
cd ../02-deps && terraform destroy
cd ../01-network && terraform destroy

# Re-apply in order
cd terraform/01-network && terraform apply
cd ../02-deps && terraform apply
cd ../03-app && terraform apply
```

## Troubleshooting

### Pods Not Starting

Check pod status and logs:

```bash
kubectl get pods -n langfuse
kubectl describe pod <pod-name> -n langfuse
kubectl logs <pod-name> -n langfuse
```

### Database Connection Errors

Verify RDS security group allows traffic from EKS nodes:

```bash
cd terraform/02-deps
terraform output rds_endpoint
terraform output -json | jq
```

Check that the RDS endpoint is reachable from a pod:

```bash
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <rds-endpoint> -U langfuse -d langfuse
```

### S3 Access Issues

Verify the IRSA role is correctly annotated on the service account:

```bash
kubectl get sa langfuse -n langfuse -o yaml | grep eks.amazonaws.com/role-arn
```

Check pod environment variables:

```bash
kubectl exec -n langfuse <langfuse-web-pod> -- env | grep AWS
```

### Terraform State Issues

If you encounter state lock errors, check Terraform Cloud:
- Go to your workspace → **States** tab
- Manually unlock if needed

### Environment Variables Not Loading

If `source .env` doesn't work or you get "organization must be set" errors:

**Check if variables are exported:**
```bash
env | grep TF_CLOUD
```

If empty, the variables weren't loaded. Try:

**Option 1: Use set -a (auto-export)**
```bash
set -a
source .env
set +a
```

**Option 2: Copy/paste export commands**
1. Open `.env` in your editor
2. Copy all the `export` lines
3. Paste directly into your terminal
4. Verify: `echo $TF_VAR_tfc_organization`

**Common issues:**
- `.env` file has syntax errors (missing quotes, extra spaces)
- Using a shell that doesn't support `export` (unlikely with bash/zsh)
- Variables not persisting across terminal sessions (this is normal - re-run `source .env`)

## Cost Breakdown

Approximate monthly costs (eu-central-1, on-demand pricing):

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| EKS Control Plane | - | $72 |
| EC2 Instances | 2x t3.medium | ~$60 |
| RDS PostgreSQL | db.t4g.micro | ~$15 |
| EBS Volumes | gp3 (for ClickHouse) | ~$5 |
| S3 Storage | Standard | ~$1 (usage-based) |
| Data Transfer | - | ~$2 (usage-based) |
| **Total** | | **~$155/month** |

**Cost optimization:**
- Destroy workspace 3 when not in use → saves ~$65/mo (EKS nodes + control plane prorated)
- Use Spot instances (future enhancement)
- Switch to Fargate for lower baseline cost (requires architecture change)

## Architecture Details

### Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Container Orchestration | AWS EKS | 1.35 |
| Infrastructure-as-Code | Terraform | ~> 1.9 |
| Package Manager | Helm | 3.x |
| Application Database | PostgreSQL (RDS) | 16 |
| Object Storage | S3 | - |
| Analytics Database | ClickHouse | 24.x (bundled) |
| Cache/Queue | Redis | 7.x (bundled) |

### Terraform Modules

- VPC: `terraform-aws-modules/vpc/aws` ~> 6.6
- EKS: `terraform-aws-modules/eks/aws` ~> 21.15
- RDS: `terraform-aws-modules/rds/aws` ~> 7.1
- IAM: `terraform-aws-modules/iam/aws` ~> 6.4
- Langfuse Helm Chart: `langfuse/langfuse` ~> 1.5

### Security Notes

**Development Environment Tradeoffs:**
- RDS is publicly accessible (port 5432 open to `0.0.0.0/0`) — protected by auto-generated password
- EKS cluster endpoint is public — allows kubectl from local machine
- No NAT gateway — nodes run in public subnets
- S3 access uses IRSA (short-lived tokens) — no static AWS credentials in pods

**For Production:**
- Place RDS and EKS nodes in private subnets
- Add NAT gateway for outbound traffic
- Enable RDS deletion protection and automated backups
- Add ingress controller + TLS + Route53 DNS
- Use AWS Secrets Manager via External Secrets Operator
- Enable VPC flow logs and GuardDuty

## Project Structure

```
langfuse-k8s-cluster/
├── .env.example                  # Environment template
├── .gitignore                    # Excludes .env and Terraform state
├── README.md                     # This file
│
└── terraform/
    ├── 01-network/               # Workspace: langfuse-network
    │   ├── providers.tf          # TFC backend, AWS provider
    │   ├── vpc.tf                # VPC module
    │   ├── eks.tf                # EKS module + EBS CSI addon
    │   ├── variables.tf          # Input variables
    │   └── outputs.tf            # Outputs for downstream workspaces
    │
    ├── 02-deps/                  # Workspace: langfuse-deps
    │   ├── providers.tf
    │   ├── data.tf               # tfe_outputs from ws1
    │   ├── rds.tf                # RDS module
    │   ├── s3.tf                 # S3 bucket
    │   ├── irsa.tf               # IAM role for S3 access
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── 03-app/                   # Workspace: langfuse-app
        ├── providers.tf          # TFC backend, AWS + Helm + K8s providers
        ├── data.tf               # tfe_outputs from ws1 + ws2
        ├── secrets.tf            # Auto-generated secrets
        ├── helm.tf               # Helm release
        ├── values.yaml.tpl       # Helm values template
        └── variables.tf
```

## Contributing

This is a learning/development project. For production deployments, consider:
- [Official Langfuse Terraform AWS Module](https://github.com/langfuse/langfuse-terraform-aws) (Fargate-based)
- Kubernetes operators for ClickHouse and Redis
- GitOps workflows (ArgoCD, FluxCD)

## License

This project is provided as-is for educational purposes.

## Support

For Langfuse-specific questions, see the [official documentation](https://langfuse.com/docs).

For infrastructure issues, check the Terraform module documentation:
- [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [terraform-aws-modules/rds](https://registry.terraform.io/modules/terraform-aws-modules/rds/aws/latest)
