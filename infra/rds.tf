resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "default" {
  name       = "cjj-default-vpc"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier                 = "cjj-postgres"
  engine                     = "postgres"
  engine_version             = var.rds_engine_version
  instance_class             = var.rds_instance_class
  allocated_storage          = 20
  storage_type               = "gp3"
  db_name                    = "app"
  username                   = "postgres"
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.default.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
}
