terraform {
  required_providers {
    aws = {
      source  = "registry.terraform.io/hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {}
provider "random" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

locals {
  use_existing_subnets = length(var.subnet_ids) >= 2
  private_subnet_ids   = local.use_existing_subnets ? var.subnet_ids : aws_subnet.private[*].id
  available_offsets = [
    for n in range(2, 250) : n
    if !anytrue(flatten([
      for s in data.aws_subnet.existing : [
        cidrcontains(s.cidr_block, cidrhost(cidrsubnet(data.aws_vpc.default.cidr_block, 8, n), 0)),
        cidrcontains(cidrsubnet(data.aws_vpc.default.cidr_block, 8, n), cidrhost(s.cidr_block, 0)),
        cidrcontains(s.cidr_block, cidrhost(cidrsubnet(data.aws_vpc.default.cidr_block, 8, n + 1), 0)),
        cidrcontains(cidrsubnet(data.aws_vpc.default.cidr_block, 8, n + 1), cidrhost(s.cidr_block, 0)),
      ]
    ]))
  ]
  subnet_offset = local.available_offsets[0]
}

# Create private subnets only if mode is "create"
resource "aws_subnet" "private" {
  count             = local.use_existing_subnets ? 0 : 2
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = cidrsubnet(data.aws_vpc.default.cidr_block, 8, local.subnet_offset + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "aurora-private-${random_pet.cluster.id}-${count.index}"
  }

  lifecycle {
    ignore_changes = [cidr_block]
  }
}

# Create a private route table (no IGW route = isolated)
resource "aws_route_table" "private" {
  count  = local.use_existing_subnets ? 0 : 1
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "aurora-private-rt"
  }
}

# Associate new subnets with private route table
resource "aws_route_table_association" "private" {
  count          = local.use_existing_subnets ? 0 : 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

resource "random_pet" "cluster" {
}

resource "aws_db_subnet_group" "private" {
  name       = random_pet.cluster.id
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "Subnet Group for ${random_pet.cluster.id} Aurora Cluster"
  }
}

resource "aws_security_group" "cluster" {
  name = "db-cluster-${random_pet.cluster.id}"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_postgres_inbound" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "random_pet" "db_name" {
  length = 1
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "serverless-${random_pet.cluster.id}"
  family = "aurora-postgresql${split(".", var.db_version)[0]}"

  parameter {
    name  = "rds.force_ssl"
    value = var.require_ssl ? "1" : "0"
  }
}

locals {
  scale_to_zero = var.minimum_acu == 0

  # A persistent TCP connection pool keeps the cluster awake, defeating
  # scale-to-zero. So when scale-to-zero is on we enable the RDS Data API
  # (connectionless) and expose the cluster/secret ARNs for it. The Data API
  # is only supported on recent Aurora PostgreSQL minor versions; these are
  # the per-major floors. See AWS Data API region/version availability docs.
  data_api_min_minor = {
    "13" = 11
    "14" = 8
    "15" = 3
    "16" = 1
    "17" = 4
  }

  db_major           = split(".", var.db_version)[0]
  db_minor           = tonumber(try(split(".", var.db_version)[1], 0))
  data_api_supported = contains(keys(local.data_api_min_minor), local.db_major) && local.db_minor >= lookup(local.data_api_min_minor, local.db_major, 9999)
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "serverless-${random_pet.cluster.id}"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = var.db_version
  db_subnet_group_name            = aws_db_subnet_group.private.name
  database_name                   = random_pet.db_name.id
  master_username                 = random_pet.db_name.id
  master_password                 = random_password.db_password.result
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  skip_final_snapshot             = true
  # Enable the connectionless Data API only when scaling to zero, so a
  # consumer's connection pool can't keep the cluster from pausing.
  enable_http_endpoint = local.scale_to_zero
  vpc_security_group_ids = [
    aws_security_group.cluster.id,
  ]


  serverlessv2_scaling_configuration {
    max_capacity = var.maximum_acu
    min_capacity = var.minimum_acu
    # Auto-pause (scale-to-zero) is only valid when min capacity is 0.
    seconds_until_auto_pause = var.minimum_acu == 0 ? var.seconds_until_auto_pause : null
  }

  lifecycle {
    precondition {
      condition     = !local.scale_to_zero || local.data_api_supported
      error_message = "Scale-to-zero (minimum_acu = 0) relies on the RDS Data API, which is only supported on Aurora PostgreSQL >= 13.11, 14.8, 15.3, 16.1, or 17.4. db_version = \"${var.db_version}\" does not support it; raise db_version or set minimum_acu > 0."
    }
  }
}

resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.private.name
}

resource "aws_ssm_parameter" "db_url" {
  name  = "/rds/${random_pet.cluster.id}/db_url"
  type  = "SecureString"
  value = "postgresql://${random_pet.db_name.id}:${urlencode(random_password.db_password.result)}@${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${random_pet.db_name.id}?sslmode=${var.require_ssl ? "verify-full" : "disable"}"
}

# The Data API authenticates via a Secrets Manager secret (not a raw password),
# so we provision one with the master credentials when scale-to-zero is on.
resource "aws_secretsmanager_secret" "master" {
  count = local.scale_to_zero ? 1 : 0
  name  = "rds-${random_pet.cluster.id}-master"
}

resource "aws_secretsmanager_secret_version" "master" {
  count     = local.scale_to_zero ? 1 : 0
  secret_id = aws_secretsmanager_secret.master[0].id
  secret_string = jsonencode({
    username = random_pet.db_name.id
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_rds_cluster.this.endpoint
    port     = aws_rds_cluster.this.port
    dbname   = random_pet.db_name.id
  })
}

# Expose the secret ARN via SSM as a plain String so Hereya passes the ARN
# itself to consumers (for the Data API) rather than resolving the contents.
resource "aws_ssm_parameter" "secret_arn" {
  count = local.scale_to_zero ? 1 : 0
  name  = "/rds/${random_pet.cluster.id}/secret_arn"
  type  = "String"
  value = aws_secretsmanager_secret.master[0].arn
}

output "DB_NAME" {
  value = random_pet.db_name.id
}

data "aws_region" "current" {}

# Standard connection string — always available, backward compatible.
output "POSTGRES_URL" {
  value = aws_ssm_parameter.db_url.arn
}

# Data API outputs — populated only when scale-to-zero is active. Consumers
# use these with a connectionless client (e.g. drizzle-orm/aws-data-api/pg).
output "CLUSTER_ARN" {
  value = local.scale_to_zero ? aws_rds_cluster.this.arn : null
}

output "SECRET_ARN" {
  value = local.scale_to_zero ? aws_ssm_parameter.secret_arn[0].arn : null
}

output "AWS_REGION" {
  value = data.aws_region.current.name
}

output "IAM_POLICY_AURORA_DATA_API" {
  value = local.scale_to_zero ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction",
        ]
        Resource = aws_rds_cluster.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.master[0].arn
      },
    ]
  }) : null
}