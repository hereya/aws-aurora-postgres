# AWS Aurora PostgreSQL

A Hereya package that provisions an AWS Aurora Serverless V2 PostgreSQL cluster with automatic scaling and secure credential management. This is the production deployment package for [hereya/postgres](https://github.com/hereya/postgres), which provides Docker-based PostgreSQL for local development.

## Overview

This package (`hereya/aws-aurora-postgres`) creates a fully managed Aurora Serverless V2 PostgreSQL database cluster on AWS, including:
- Aurora Serverless V2 cluster with configurable compute scaling
- Automatic password generation and secure storage in AWS Systems Manager (SSM)
- VPC security group configuration for database access
- Database subnet group using private subnets

## Prerequisites

- AWS account with appropriate permissions for RDS, VPC, SSM, and EC2
- VPC with private subnets tagged with `Tier=private`
- Hereya CLI installed

## Package Relationship

This package (`hereya/aws-aurora-postgres`) is the **automatic production deployment** package for [hereya/postgres](https://github.com/hereya/postgres).

**How it works:**
1. Install only `hereya/postgres` for your project: `hereya add hereya/postgres`
2. Use Docker-based PostgreSQL for local development
3. When you run `hereya deploy` with the production profile, this AWS Aurora package is automatically deployed instead
4. Configure all parameters (both development and production) in a single file: `hereyaconfig/hereyavars/hereya--postgres.yaml`

**You do NOT need to manually add this package** - it's automatically used during deployment.

## Installation

This package is **automatically deployed** when you use `hereya deploy` with `hereya/postgres`. You don't install it directly.

### Setup Process

1. **Install the base package**:
```bash
# Install hereya/postgres for development
hereya add hereya/postgres
```

2. **Configure parameters** in `hereyaconfig/hereyavars/hereya--postgres.yaml`:
```yaml
# Development parameters (Docker PostgreSQL)
port: 5432
---
# Production profile (AWS Aurora parameters)
profile: production
minimum_acu: 4.0
maximum_acu: 32.0
db_version: "15.4"
```

3. **Create production workspace and deploy**:
```bash
# Create a production workspace with the production profile
hereya workspace create prod --profile production

# Deploy to production workspace (automatically uses hereya/aws-aurora-postgres)
hereya deploy -w prod
```

## Parameters

These parameters are configured in `hereyaconfig/hereyavars/hereya--postgres.yaml` under the appropriate profile section:

| Parameter | Type | Required | Description | Default | Valid Range |
|-----------|------|----------|-------------|---------|-------------|
| `minimum_acu` | number | No | Minimum Aurora Capacity Units for auto-scaling | `0.5` | 0.5 - 128 |
| `maximum_acu` | number | No | Maximum Aurora Capacity Units for auto-scaling | `4.0` | 0.5 - 128 |
| `db_version` | string | No | PostgreSQL engine version | `14.9` | Check AWS for supported versions |

### Aurora Capacity Units (ACUs)

Each ACU provides approximately:
- 2 GiB of memory
- Corresponding CPU and network resources

Common configurations:
- **Development**: 0.5 - 1.0 ACUs
- **Testing**: 0.5 - 4.0 ACUs (default)
- **Production**: 2.0 - 16.0 ACUs or higher

## Usage Examples

### Complete Development to Production Setup

1. **Install hereya/postgres**:
```bash
hereya add hereya/postgres
```

2. **Create parameter file** `hereyaconfig/hereyavars/hereya--postgres.yaml`:

```yaml
# Development configuration (Docker PostgreSQL)
port: 5432
---
# Staging profile
profile: staging
# AWS Aurora parameters for staging deployment
minimum_acu: 0.5
maximum_acu: 2.0
db_version: "14.9"
---
# Production profile  
profile: production
# AWS Aurora parameters for production deployment
minimum_acu: 4.0
maximum_acu: 32.0
db_version: "15.4"
```

3. **Development workflow**:
```bash
# Local development uses Docker PostgreSQL
hereya up
```

4. **Staging deployment**:
```bash
# Create staging workspace
hereya workspace create staging --profile staging

# Deploy to staging (automatically uses AWS Aurora)
hereya deploy -w staging
```

5. **Production deployment**:
```bash
# Create production workspace
hereya workspace create production --profile production

# Deploy to production (automatically uses AWS Aurora)
hereya deploy -w production
```

## Outputs

After deployment, this package exports environment variables that are automatically available when running your application:

| Environment Variable | Description | Example |
|---------------------|-------------|---------|
| `DB_NAME` | Database name (randomly generated) | `cuddly-owl` |
| `POSTGRES_URL` | Full PostgreSQL connection string | `postgresql://username:password@endpoint:5432/database` |

The connection string is securely stored in AWS Systems Manager Parameter Store and automatically decrypted when your application runs.

## Infrastructure Details

### Network Configuration

- **Subnet Group**: Uses private subnets tagged with `Tier=private`
- **Security Group**: Configured for PostgreSQL port 5432
  - ⚠️ Default allows access from 0.0.0.0/0 (modify for production)
- **Availability**: Multi-AZ deployment across available private subnets

### Security Features

- **Password Management**: Randomly generated 20-character password
- **Credential Storage**: Encrypted SecureString in AWS SSM Parameter Store
- **Network Isolation**: Database deployed in private subnets
- **IAM Integration**: Supports IAM database authentication (can be enabled)

### Scaling Behavior

Aurora Serverless V2 automatically scales based on database load:
- Scales up within seconds when load increases
- Scales down during periods of low activity
- Maintains connections during scaling operations
- Billed per ACU-hour based on actual usage

## Flow Commands

For git branch-based development workflows:

```bash
# Add hereya/postgres to branch workspace (inherits profile from base workspace)
hereya flow add hereya/postgres

# Deploy branch-specific infrastructure (uses Docker locally)
hereya flow up

# View outputs
hereya flow env

# Destroy when branch is merged
hereya flow down
```

## Troubleshooting

### Common Issues

1. **Subnet Not Found Error**
   - Ensure your VPC has subnets tagged with `Tier=private`
   - Verify subnets are in at least 2 availability zones

2. **Permission Denied**
   - Verify AWS credentials have permissions for:
     - RDS (cluster and instance creation)
     - VPC (security groups, subnet groups)
     - SSM (parameter creation)
     - EC2 (describe operations)

3. **Connection Timeout**
   - Check security group rules allow access from your application
   - Verify application is in same VPC or has VPC peering configured
   - Ensure route tables are properly configured

4. **Scaling Issues**
   - Monitor CloudWatch metrics for ACU utilization
   - Adjust minimum_acu if experiencing cold starts
   - Increase maximum_acu if hitting capacity limits

## Best Practices

### Production Recommendations

1. **Security Group**: Restrict access to specific CIDR blocks or security groups
2. **Backup**: Configure automated backups and retention period
3. **Encryption**: Enable encryption at rest and in transit
4. **Monitoring**: Set up CloudWatch alarms for key metrics
5. **High Availability**: Ensure adequate ACU minimums for failover scenarios

### Cost Optimization

- Use lower minimum_acu for development/testing environments
- Monitor actual ACU usage to right-size maximum_acu
- Consider Aurora Serverless V1 for intermittent workloads
- Enable auto-pause for development databases (requires code modification)

## Dependencies

This package requires:
- AWS Provider for Terraform ~> 5.0
- Random Provider for Terraform ~> 3.5
- Existing VPC with properly tagged private subnets

## Support

For issues or questions:
- Create an issue in the package repository
- Check AWS RDS documentation for Aurora-specific details
- Review Terraform AWS provider documentation for resource configuration options

## License

MIT