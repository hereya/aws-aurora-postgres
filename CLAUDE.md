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
   - `minimum_acu`: Min Aurora Compute Units (default: 0.5)
   - `maximum_acu`: Max Aurora Compute Units (default: 4.0)
   - `db_version`: PostgreSQL version (default: "14.9")

3. **hereyarc.yaml**: Hereya configuration specifying:
   - Infrastructure as Code tool: Terraform
   - Target infrastructure: AWS

### Key Design Patterns

- **Resource Naming**: Uses `random_pet` for unique cluster identification
- **Security**: Passwords generated via `random_password` and stored encrypted in SSM
- **Networking**: Database placed in private subnets identified by tags
- **Outputs**: Exposes `DB_NAME` and `POSTGRES_URL` (SSM parameter ARN)

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