provider "aws" {
  region = "us-east-1"
}

variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable avail_zone {}
variable env_prefix {}
variable my_ip {}
variable instance_type{}
variable user_name {}
variable password {}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name: "${var.env_prefix}-vpc"
  }
}
resource "aws_subnet" "myapp-subnet-1" {
  vpc_id = aws_vpc.myapp-vpc.id
  cidr_block = var.subnet_cidr_block
  availability_zone = var.avail_zone
  tags = {
    Name: "${var.env_prefix}-subnet-1"
  }
}
resource "aws_route_table" "myapp-route-table" {
  vpc_id = aws_vpc.myapp-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }
  tags = {
    Name: "${var.env_prefix}-rtb"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name: "${var.env_prefix}-igw"
  }
}
resource "aws_route_table_association" "a-rtb-subnet" {
  subnet_id = aws_subnet.myapp-subnet-1.id
  route_table_id = aws_route_table.myapp-route-table.id
}
resource "aws_security_group" "myapp-sg" {
  name = "myapp-sg"
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    prefix_list_ids = []
  }
  tags = {
    Name: "${var.env_prefix}-sg"
  }
}

resource "aws_iam_role_policy" "my_policy" {
  name = "my_policy"
  role = aws_iam_role.my_role.id

# Terraform "jsonencode" function converts a
# Terraform expression result to valid JSON syntax.
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Action = [
        "ec2:Describe*",
      ]
      Effect   = "Allow"
      Resource = "*"
    },
  ]
})
}
resource "aws_iam_role" "my_role" {
  name = "my_role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}
resource "aws_lb" "my-balancer" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.myapp-sg.id]
  subnets            = [aws_subnet.myapp-subnet-1.id]
}

resource "aws_efs_file_system" "my-file" {
  creation_token = "my-efs"
  performance_mode = "generalPurpose"  # Options: generalPurpose, maxIO
}

# Create a mount target for the EFS in the subnet
resource "aws_efs_mount_target" "mount_target" {
  file_system_id = aws_efs_file_system.my-file.id
  subnet_id      = aws_subnet.myapp-subnet-1.id
}

resource "aws_ecs_cluster" "my-cluster" {
  name = "my-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "example" {
  cluster_name = aws_ecs_cluster.my-cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_rds_cluster" "my-db" {
  cluster_identifier        = "my-cluster"
  availability_zones        = ["us-east-1a"]
  engine                    = "mysql"
  db_cluster_instance_class = "db.r6gd.xlarge"
  storage_type              = "io1"
  allocated_storage         = 100
  iops                      = 1000
  master_username           = var.user_name
  master_password           = var.password
}

resource "aws_ecs_task_definition" "wordpress" {
  family                = "service"
  container_definitions = file("\Users\BELLO OPEYEMI\IdeaProjects\terraform\wordpress.json")

  volume {
    name = "service-storage"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.my-file.id
      root_directory          = "/opt/data"
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.access-point.id
        iam             = "ENABLED"
      }
    }
  }
}

resource "aws_efs_access_point" "access-point" {
  file_system_id = aws_efs_file_system.my-file.id
}

resource "aws_ecs_service" "wordpress" {
  name          = "wordpress"
  cluster       = aws_ecs_cluster.my-cluster.id
  desired_count = 2
}