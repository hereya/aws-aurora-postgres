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

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  tags = {
    Tier = "private"
  }
}


resource "random_pet" "cluster" {
}

resource "aws_db_subnet_group" "private" {
  name       = random_pet.cluster.id
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name = "Subnet Group for ${random_pet.cluster.id} Aurora Cluster "
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

resource "aws_rds_cluster" "this" {
  cluster_identifier     = "serverless-${random_pet.cluster.id}"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  engine_version         = var.db_version
  db_subnet_group_name   = aws_db_subnet_group.private.name
  database_name          = random_pet.db_name.id
  master_username        = random_pet.db_name.id
  master_password        = random_password.db_password.result
  skip_final_snapshot    = true
  vpc_security_group_ids = [
    aws_security_group.cluster.id,
  ]


  serverlessv2_scaling_configuration {
    max_capacity = var.maximum_acu
    min_capacity = var.minimum_acu
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
  value = "postgresql://${random_pet.db_name.id}:${urlencode(random_password.db_password.result)}@${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${random_pet.db_name.id}"
}

output "DB_NAME" {
  value = random_pet.db_name.id
}

data "aws_region" "current" {}

output "POSTGRES_URL" {
  value = aws_ssm_parameter.db_url.arn
}