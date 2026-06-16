# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hereya package that provides Terraform infrastructure-as-code for deploying AWS Aurora Serverless V2 PostgreSQL clusters. It's designed as a reusable module within the Hereya ecosystem.

## Common Commands

### Terraform Operations
```bash
# Initialize Terraform providers and modules
terraform init

# Validate configuration syntax
terraform validate

# Preview infrastructure changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy infrastructure
terraform destroy

# Format Terraform files
terraform fmt
```

### Development Workflow
```bash
# Check Terraform formatting
terraform fmt -check

# Validate Terraform configuration
terraform validate

# Generate detailed plan output
terraform plan -out=tfplan

# Apply specific plan
terraform apply tfplan
```

## Architecture and Structure

### Core Components

1. **main.tf**: Defines the Aurora Serverless V2 cluster with:
   - RDS cluster with PostgreSQL engine (configurable version via `db_version` variable)
   - Serverless V2 scaling configuration (ACU range: `minimum_acu` to `maximum_acu`)
   - Single writer instance using `db.serverless` compute class
   - Security group allowing PostgreSQL access on port 5432
   - DB subnet group using private subnets (tagged with `Tier=private`)
   - SSM parameter storing encrypted connection URL at `/rds/{cluster-id}/db_url`

2. **variables.tf**: Input parameters for customization:
   - `minimum_acu`: Min Aurora Compute Units (default: 0.5). Set to `0` to enable scale-to-zero.
   - `maximum_acu`: Max Aurora Compute Units (default: 4.0)
   - `seconds_until_auto_pause`: Idle seconds before scaling to zero, only used when `minimum_acu` is 0 (default: 300, range 300-86400)
   - `db_version`: PostgreSQL version (default: "17.6")
   - `require_ssl`: Require SSL connections (default: false)
   - `subnet_ids`: Optional user-provided subnets (default: [], creates private subnets if empty)

3. **hereyarc.yaml**: Hereya configuration specifying:
   - Infrastructure as Code tool: Terraform
   - Target infrastructure: AWS

### Key Design Patterns

- **Resource Naming**: Uses `random_pet` for unique cluster identification
- **Security**: Passwords generated via `random_password` and stored encrypted in SSM
- **Networking**: Database placed in private subnets identified by tags
- **Outputs**: Always exposes `DB_NAME` and `POSTGRES_URL` (SSM parameter ARN). When scale-to-zero is active (`minimum_acu == 0`), also exposes `CLUSTER_ARN`, `SECRET_ARN`, `AWS_REGION`, and `IAM_POLICY_AURORA_DATA_API` for Data API consumers (null otherwise).

### Scale-to-Zero & Data API

- Setting `minimum_acu = 0` sets `seconds_until_auto_pause` on the cluster so it auto-pauses when idle.
- A persistent connection pool keeps the cluster awake and defeats auto-pause, so scale-to-zero also enables the **RDS Data API** (`enable_http_endpoint`) and provisions a Secrets Manager secret with the master credentials (the Data API authenticates via a secret, not a raw password). Consumers should use a connectionless client like `drizzle-orm/aws-data-api/pg`.
- The Data API requires Aurora PostgreSQL >= 13.11 / 14.8 / 15.3 / 16.1 / 17.4. A `lifecycle precondition` on the cluster blocks `apply` when `minimum_acu = 0` is combined with an unsupported `db_version`.
- `local.scale_to_zero` and `local.data_api_supported` (in main.tf) drive all of this conditional behavior; the Data API resources/outputs use `count` so the default (always-on) path is unchanged and backward compatible.

### Important Dependencies

- **AWS Provider**: Version ~> 5.0
- **Random Provider**: Version ~> 3.5
- **VPC Requirements**: Expects existing VPC with subnets tagged `Tier=private`
- **Region**: Uses data source to determine current AWS region

## Critical Implementation Details

### Security Group Configuration
The security group currently allows broad access (0.0.0.0/0) on port 5432. When modifying, ensure to:
- Update CIDR blocks to restrict access
- Maintain PostgreSQL port (5432) configuration
- Consider VPC peering or PrivateLink for cross-VPC access

### SSM Parameter Storage
Connection strings are stored as SecureString in SSM with format:
```
postgresql://{username}:{password}@{endpoint}:{port}/{database}
```

### Cluster Configuration
- Engine: `aurora-postgresql` with serverless V2
- Auto scaling between minimum and maximum ACUs
- Scale-to-zero (auto-pause) when `minimum_acu == 0`, with the Data API enabled (see above)
- Skip final snapshot enabled (modify for production use)
- No explicit encryption configuration (relies on defaults)

## Testing Approach

Currently no automated tests. When implementing tests:
1. Use `terraform validate` for syntax checking
2. Use `terraform plan` to verify changes
3. Consider implementing Terratest for infrastructure testing
4. Validate SSM parameter creation and accessibility

## Common Issues and Solutions

1. **Subnet Not Found**: Ensure VPC has subnets tagged with `Tier=private`
2. **Permission Errors**: Verify AWS credentials have RDS, VPC, SSM, and EC2 permissions
3. **Cluster Creation Timeout**: Check VPC connectivity and subnet configuration
4. **SSM Parameter Access**: Ensure consuming services have IAM permissions for SSM GetParameter

## Integration with Hereya Ecosystem

This module is part of the Hereya registry. When updating:
- Maintain compatibility with `hereyarc.yaml` format
- Ensure outputs match expected Hereya interface
- Follow Hereya naming conventions for resources