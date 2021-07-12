#-------------------------------------------------
# Terraform
#
# Create:
# - Security Groups for Web Server, RDS and EFS
# - Launch Configuration with Auto AMI Lookup
# - Auto Scaling Group using 2 Availability Zones
# - Classic Load Balancer in 2 Availability Zones
#
#
#-------------------------------------------------

provider "aws" {
    region = "eu-west-2"
    }

data "aws_availability_zones" "available" {}

data "aws_ami" "latest-amazon2" {
    owners = ["amazon"]
    most_recent = true
    filter {
      name = "name"
      values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

#-------------------------------------------------
#
# Security
#
#-------------------------------------------------

resource "aws_vpc" "epm-vpc-main" {
  cidr_block            = "10.10.0.0/16"
  instance_tenancy      = "default"
  enable_dns_hostnames  = true
}

resource "aws_security_group" "epm-sg-web" {
  name = "epm-sg-web"
  description    = "Allow web traffic"
  vpc_id  = aws_vpc.epm-vpc-main.id

  dynamic "ingress" {
      for_each = ["22","80","443"]
    content {
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
  }
} 
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "epm-sg-db" {
  name = "epm-sg-db"
  description = "Allow SQL traffic"
  vpc_id = aws_vpc.epm-vpc-main.id
}

resource "aws_security_group_rule" "epm-sg-db-in" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.epm-sg-web.id
  security_group_id        = aws_security_group.epm-sg-db.id
}

resource "aws_security_group_rule" "epm-sg-db-out" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.epm-sg-db.id
}

resource "aws_security_group" "epm-sg-efs" {
  name = "epm-sg-efs"
  description = "Allow NFS traffic "
  vpc_id      = aws_vpc.epm-vpc-main.id
  }

resource "aws_security_group_rule" "epm-sg-efs-in" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.epm-sg-web.id
  security_group_id        = aws_security_group.epm-sg-efs.id
  }

resource "aws_security_group_rule" "epm-sg-efs-out" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.epm-sg-efs.id
}

#-------------------------------------------------
#
# Network and Routing
#
#-------------------------------------------------

resource "aws_internet_gateway" "epm-igw" {
  vpc_id = aws_vpc.epm-vpc-main.id
}

resource "aws_subnet" "epm-pub-net-1" {
  vpc_id                  = aws_vpc.epm-vpc-main.id
  cidr_block              = "10.10.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "epm-pub-net-2" {
  vpc_id                  = aws_vpc.epm-vpc-main.id
  cidr_block              = "10.10.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "epm-rt-pub" {
  vpc_id = aws_vpc.epm-vpc-main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.epm-igw.id
  }
}

resource "aws_route_table_association" "epm-rta-1" {
  subnet_id      = aws_subnet.epm-pub-net-1.id
  route_table_id = aws_route_table.epm-rt-pub.id
}

resource "aws_route_table_association" "epm-rta-2" {
  subnet_id      = aws_subnet.epm-pub-net-2.id
  route_table_id = aws_route_table.epm-rt-pub.id
}

#-------------------------------------------------
#
# Load Balancer
#
#-------------------------------------------------

resource "aws_lb_target_group" "alb-tg" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  name        = "alb-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.epm-vpc-main.id
}

resource "aws_lb_target_group_attachment" "alb-tg-1" {
  target_group_arn = aws_lb_target_group.alb-tg.arn
  target_id        = aws_instance.epm-srv-web-1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "alb-tg-2" {
  target_group_arn = aws_lb_target_group.alb-tg.arn
  target_id        = aws_instance.epm-srv-web-2.id
  port             = 80
}

resource "aws_lb" "app-lb" {
  name                       = "app-lb"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  security_groups            = [aws_security_group.epm-sg-web.id]
  enable_deletion_protection = false
}

resource "aws_lb_listener" "list-alb" {
  load_balancer_arn = aws_lb.app-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

#-------------------------------------------------
#
# Instance and storage
#
#-------------------------------------------------

resource "aws_instance" "epm-srv-web-1" {
  ami = data.aws_ami.latest-amazon2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.epm-pub-net-1.id
  vpc_security_group_ids = [aws_security_group.epm-sg-web.id]
  user_data = <<EOF
#!/bin/bash
sudo yum -y update
sudo yum -y install httpd
sudo rm -r /var/www/html/*
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name}:/ /var/www/html
sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz
sudo rsync -avP ~/wordpress/ /var/www/html/
sudo wget https://raw.githubusercontent.com/madmongoose/epam/main/terraform/wp-config.php
sudo mv wp-config.php /var/www/html/wp-config.php
sudo chown -R apache /var/www
sudo chgrp -R apache /var/www
sudo chmod 2775 /var/www
find /var/www -type d -exec sudo chmod 2775 {} \;
find /var/www -type f -exec sudo chmod 0664 {} \;
sudo rm latest.tar.gz
sudo systemctl enable httpd
sudo systemctl start httpd
sudo yum -y install php-fpm php-gd php-pdo php-mbstring php-pear
sudo systemctl enable php-fpm
sudo systemctl start php-fpm
EOF
depends_on = [aws_efs_file_system.epm-efs, module.db]
}

resource "aws_instance" "epm-srv-web-2" {
  ami = data.aws_ami.latest-amazon2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.epm-pub-net-2.id
  vpc_security_group_ids = [aws_security_group.epm-sg-web.id]
  user_data = <<EOF
#!/bin/bash
sudo yum -y update
sudo yum -y install httpd
sudo rm -r /var/www/html/*
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_mount_target.epm-efs-mt-2.mount_target_dns_name}:/ /var/www/html
sudo yum -y install php-fpm php-gd php-pdo php-mbstring php-pear
sudo chown -R apache /var/www
sudo chgrp -R apache /var/www
sudo chmod 2775 /var/www
find /var/www -type d -exec sudo chmod 2775 {} \;
find /var/www -type f -exec sudo chmod 0664 {} \;
sudo rm latest.tar.gz
sudo systemctl enable httpd
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start httpd
sudo systemctl enable php-fpm
sudo systemctl start php-fpm
EOF
depends_on = [aws_efs_file_system.epm-efs, module.db]
}

resource "aws_efs_file_system" "epm-efs" {
  creation_token = "epm-efs"
  encrypted      = "false"
  }

resource "aws_efs_mount_target" "epm-efs-mt-1" {
  file_system_id  = aws_efs_file_system.epm-efs.id
  subnet_id       = aws_subnet.epm-pub-net-1.id
  security_groups = [aws_security_group.epm-sg-efs.id]
  }

resource "aws_efs_mount_target" "epm-efs-mt-2" {
  file_system_id  = aws_efs_file_system.epm-efs.id
  subnet_id       = aws_subnet.epm-pub-net-2.id
  security_groups = [aws_security_group.epm-sg-efs.id]
  }

#-------------------------------------------------
#
# RDS
#
#-------------------------------------------------

/*resource "random_string" "mmg-rds-pass" {
  length           = 10
  special          = true
  override_special = "!#$&"

  keepers = {
    kepeer1 = var.name
  }
}*/

/*resource "aws_ssm_parameter" "mmg-rds-pass" {
  name        = "mmg-mysql"
  description = "Admin password for MySQL"
  type        = "SecureString"
  value       = random_string.mmg-rds-pass.result
}

data "aws_ssm_parameter" "mmg-rds-pass" {
  name       = "mmg-mysql"
  depends_on = [aws_ssm_parameter.mmg-rds-pass]
}*/

module "db" {
  source                              = "terraform-aws-modules/rds/aws"
  version                             = "~> 3.0"
  identifier                          = "wordpress"
  engine                              = "mysql"
  engine_version                      = "5.7.26"
  instance_class                      = "db.t2.micro"
  allocated_storage                   = 5
  name                                = "wordpress"
  username                            = "admin"
  password                            = "test1234"
  port                                = "3306"
  iam_database_authentication_enabled = true
  vpc_security_group_ids              = [aws_security_group.epm-sg-db.id]
  subnet_ids                          = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  family                              = "mysql5.7"
  major_engine_version                = "5.7"
  skip_final_snapshot  = true
  apply_immediately    = true
}