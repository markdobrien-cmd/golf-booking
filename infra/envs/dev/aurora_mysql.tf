# --- Aurora MySQL (Serverless v2) ---
# A side exercise next to the plan of record (the golf services use PostgreSQL, see ADR 0002).
# Four pieces, in the order AWS needs them:
#   1. a subnet group: which subnets the database may live in (our private ones)
#   2. a security group: who may connect on port 3306 (only the EKS nodes)
#   3. the cluster: storage, engine, admin login, backups. It holds no compute on its own
#   4. an instance: the compute that answers queries. "db.serverless" scales up and down by itself

resource "aws_db_subnet_group" "mysql" {
  name        = "${local.name}-mysql"
  description = "Private subnets for the Aurora MySQL cluster"
  subnet_ids  = module.network.private_subnet_ids
}

resource "aws_security_group" "mysql" {
  name        = "${local.name}-mysql"
  description = "Aurora MySQL: allow 3306 from EKS nodes only"
  vpc_id      = module.network.vpc_id
}

# Rules live in their own resources rather than inline blocks, so adding one later doesn't
# rewrite the whole group.
resource "aws_vpc_security_group_ingress_rule" "mysql_from_nodes" {
  security_group_id            = aws_security_group.mysql.id
  description                  = "MySQL from EKS worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = module.eks.node_security_group_id
}

resource "aws_rds_cluster" "mysql" {
  cluster_identifier = "${local.name}-mysql"
  engine             = "aurora-mysql"
  engine_version     = var.mysql_engine_version
  # Serverless v2 uses the normal "provisioned" mode with db.serverless instances.
  engine_mode = "provisioned"

  database_name   = "golf"
  master_username = "golfadmin"
  # RDS generates the password and keeps it in Secrets Manager, so it never appears in code or state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]
  storage_encrypted      = true

  serverlessv2_scaling_configuration {
    # 0 ACUs: the instance pauses after `seconds_until_auto_pause` idle and costs only storage.
    # The first query after a pause waits ~15 seconds while it resumes.
    min_capacity             = 0
    max_capacity             = 2 # 1 ACU is about 2 GiB of memory
    seconds_until_auto_pause = 300
  }

  # Dev settings so the nightly teardown can delete it cleanly. Production would flip all three.
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
}

resource "aws_rds_cluster_instance" "mysql" {
  identifier         = "${local.name}-mysql-1"
  cluster_identifier = aws_rds_cluster.mysql.id
  instance_class     = "db.serverless"
  # Must match the cluster, so read them from it rather than repeat them.
  engine         = aws_rds_cluster.mysql.engine
  engine_version = aws_rds_cluster.mysql.engine_version

  publicly_accessible = false
}
