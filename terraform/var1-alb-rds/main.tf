#-------------------------------------------------
# Terraform
#
# Create:
# - Security Groups for Web Server, RDS and EFS
# - Network, IGW and Routes
# - Application Load Balancer in 2 Availability Zones
# - Instances and EFS storage
# - RDS
#
#-------------------------------------------------

provider "aws" {
    region = "eu-west-2"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
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

resource "tls_private_key" "dev_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.generated_key_name
  public_key = tls_private_key.dev_key.public_key_openssh

  provisioner "local-exec" {      # Key *.pem will be create in current directory
    command = "echo '${tls_private_key.dev_key.private_key_pem}' > ./'${var.generated_key_name}'.pem"
  }

  provisioner "local-exec" {
    command = "chmod 400 ./'${var.generated_key_name}'.pem"
  }
}

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
  tags = merge(var.common-tags, {Name = "${var.common-tags["Environment"]} Dynamic Security Group"})
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

resource "aws_lb_target_group" "epm-alb-tg" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  name        = "epm-alb-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.epm-vpc-main.id
}

resource "aws_lb_target_group_attachment" "epm-alb-tga-1" {
  target_group_arn = aws_lb_target_group.epm-alb-tg.arn
  target_id        = aws_instance.epm-srv-web-1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "epm-alb-tga-2" {
  target_group_arn = aws_lb_target_group.epm-alb-tg.arn
  target_id        = aws_instance.epm-srv-web-2.id
  port             = 80
}

resource "aws_lb" "epm-app-lb" {
  name                       = "epm-app-lb"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  security_groups            = [aws_security_group.epm-sg-web.id]
  enable_deletion_protection = false
}

resource "aws_lb_listener" "epm-alb-lr" {
  load_balancer_arn = aws_lb.epm-app-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.epm-alb-tg.arn
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
  key_name = aws_key_pair.generated_key.key_name
  user_data = <<EOF
#!/bin/bash
sudo yum -y update
sudo yum -y install httpd
sudo amazon-linux-extras install php7.4 -y
sudo rm -r /var/www/html/*
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name}:/ /var/www/html
sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz
sudo cp -r wordpress/* /var/www/html/
sudo wget https://raw.githubusercontent.com/madmongoose/epam/main/terraform/wp-config.php
sudo mv wp-config.php /var/www/html/
sudo sed -i 's/test1234/${data.aws_ssm_parameter.get-epm-rds-pass.value}/g' /var/www/html/wp-config.php
sudo sed -i 's/localhost/${module.db.db_instance_endpoint}/g' /var/www/html/wp-config.php
sudo chown -R apache /var/www
sudo chgrp -R apache /var/www
sudo chmod 2775 /var/www
sudo rm latest.tar.gz
sudo systemctl enable httpd
sudo systemctl start httpd
EOF
depends_on = [aws_efs_file_system.epm-efs, module.db]
tags = merge(var.common-tags, {Name = "${var.common-tags["Environment"]} Web Server 1"})
}

resource "aws_instance" "epm-srv-web-2" {
  ami = data.aws_ami.latest-amazon2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.epm-pub-net-2.id
  vpc_security_group_ids = [aws_security_group.epm-sg-web.id]
  key_name = aws_key_pair.generated_key.key_name
  user_data = <<EOF
#!/bin/bash
sudo yum -y update
sudo yum -y install httpd
sudo amazon-linux-extras install php7.4 -y
sudo rm -r /var/www/html/*
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_mount_target.epm-efs-mt-2.mount_target_dns_name}:/ /var/www/html
sudo sed -i 's/test1234/${data.aws_ssm_parameter.get-epm-rds-pass.value}/g' /var/www/html/wp-config.php
sudo sed -i 's/localhost/${module.db.db_instance_endpoint}/g' /var/www/html/wp-config.php
sudo yum -y install php php-gd
sudo chown -R apache /var/www
sudo chgrp -R apache /var/www
sudo chmod 2775 /var/www
sudo systemctl enable httpd
sudo systemctl start httpd
EOF
depends_on = [aws_instance.epm-srv-web-1, aws_efs_file_system.epm-efs, module.db]
tags = merge(var.common-tags, {Name = "${var.common-tags["Environment"]} Web Server 2"})
}

resource "aws_efs_file_system" "epm-efs" {
  creation_token = "epm-efs"
  encrypted      = "false"
lifecycle {
      create_before_destroy = true
    }
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

resource "random_string" "epm-rds-pass" {
  length           = 10
  special          = true
  override_special = "!#$&"

  /*keepers = {
    kepeer1 = var.name # Uncoment for change db password
  }*/
}

resource "aws_ssm_parameter" "epm-rds-pass" {
  name        = "epm-mysql"
  description = "Admin password for MySQL"
  type        = "SecureString"
  value       = random_string.epm-rds-pass.result
}

data "aws_ssm_parameter" "get-epm-rds-pass" {
  name       = "epm-mysql"
  depends_on = [aws_ssm_parameter.epm-rds-pass]
}

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
  password                            = data.aws_ssm_parameter.get-epm-rds-pass.value
  port                                = "3306"
  iam_database_authentication_enabled = true
  vpc_security_group_ids              = [aws_security_group.epm-sg-db.id]
  subnet_ids                          = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  family                              = "mysql5.7"
  major_engine_version                = "5.7"
  skip_final_snapshot  = true
  apply_immediately    = true
}
