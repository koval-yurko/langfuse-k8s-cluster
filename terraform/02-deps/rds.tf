resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds" {
  name        = "langfuse-dev-rds"
  description = "Security group for Langfuse RDS instance"
  vpc_id      = data.tfe_outputs.network.values.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow PostgreSQL from EKS nodes"
  referenced_security_group_id = data.tfe_outputs.network.values.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_public" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow PostgreSQL from any IPv4 (dev convenience)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_outbound" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

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

  # v7.x defaults manage_master_user_password to true — must disable to use our own password
  manage_master_user_password = false
  # v7.x renamed password to password_wo (write-only attribute)
  password_wo = random_password.db.result

  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rds.id]

  create_db_subnet_group = true
  subnet_ids             = data.tfe_outputs.network.values.public_subnet_ids

  deletion_protection = false
  skip_final_snapshot = true
}
