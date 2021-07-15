#-------------------------------------------------
# Terraform
#
# Create:
# - Security Groups for Web Server, RDS and EFS
# - Network, IGW and Routes
# - Launch Configuration and Autoscaling Group
# - Classic Load Balancer in 2 Availability Zones
# - RDS Cluster
#
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
      for_each = ["22","80","443","3306"]
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

resource "aws_elb" "epm-elb" {
  name = "epm-elb"
  //availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  subnets = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  security_groups = [aws_security_group.epm-sg-web.id]
  
  listener {
      lb_port = 80
      lb_protocol = "http"
      instance_port = 80
      instance_protocol = "http"
  }
  /*health_check {
      healthy_threshold = 2
      unhealthy_threshold = 2
      timeout = 3
      target = "HTTP:80/index.html"
      interval = 10*/

  health_check {
      healthy_threshold = 2
      unhealthy_threshold = 2
      timeout = 3
      target = "TCP:80"
      interval = 10
  }
  tags = merge(var.common-tags, {Name = "${var.common-tags["Environment"]} Elastic Load Balancer"})
}

#-------------------------------------------------
#
# Instance and storage
#
#-------------------------------------------------

resource "aws_launch_configuration" "epm-haweb-conf" {
  //name          = "webserver-ha-lc"
  name_prefix = "epm-haweb-conf-"
  image_id      = data.aws_ami.latest-amazon2.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.epm-sg-web.id]
  key_name = aws_key_pair.generated_key.key_name
  user_data = <<EOF
#!/bin/bash
sudo yum -y update
sudo yum -y install httpd
sudo rm -r /var/www/html/*
sudo amazon-linux-extras install php7.4 -y
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_mount_target.epm-efs-mt-1.mount_target_dns_name}:/ /var/www/html
sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz
sudo cp -r wordpress/* /var/www/html/
sudo wget https://raw.githubusercontent.com/madmongoose/epam/main/terraform/wp-config.php
sudo mv wp-config.php /var/www/html/
sudo sed -i "/DB_PASSWORD/s/'[^']*'/'${data.aws_ssm_parameter.get-epm-rds-pass.value}'/2" /var/www/html/wp-config.php
sudo sed -i "/DB_HOST/s/'[^']*'/'${aws_rds_cluster.epm-rds-cluster.endpoint}:3306'/2" /var/www/html/wp-config.php
sudo chown -R apache /var/www
sudo chgrp -R apache /var/www
sudo chmod 2775 /var/www
sudo rm latest.tar.gz
sudo systemctl enable httpd
sudo systemctl start httpd
EOF
depends_on = [aws_efs_file_system.epm-efs, aws_rds_cluster_instance.epm-rds-instances]

  lifecycle {
      create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "epm-asg" {
  name = "epm-asg-${aws_launch_configuration.epm-haweb-conf.name}"
  launch_configuration = aws_launch_configuration.epm-haweb-conf.name
  min_size = 2
  max_size = 2
  min_elb_capacity = 2
  health_check_type = "ELB"
  //vpc_zone_identifier = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  vpc_zone_identifier = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
  load_balancers = [aws_elb.epm-elb.name]

  dynamic "tag" {
    for_each = {
      Name = "Web Server in ASG"
      Owner = "Roman Gorokhovsky"
      TAGKEY = "TAGVALUE"
    }
  content {
    key = "tag.key"
    value = "tag.value"
    propagate_at_launch = true
   }
  }

    lifecycle {
      create_before_destroy = true
    }
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
# RDS Cluster
#
#-------------------------------------------------

resource "random_string" "epm-rds-pass" {
  length           = 10
  special          = true
  override_special = "!#&"

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

resource "aws_rds_cluster" "epm-rds-cluster" {

    cluster_identifier_prefix     = "epm-rds-cluster-"
    engine                        = "aurora-mysql"
    database_name                 = "wordpress"
    master_username               = "admin"
    master_password               = data.aws_ssm_parameter.get-epm-rds-pass.value
    port                          = "3306"
    backup_retention_period       = 14
    db_subnet_group_name          = aws_db_subnet_group.epm-rds-sng.name
    vpc_security_group_ids        = [aws_security_group.epm-sg-db.id]
    skip_final_snapshot           = true
    apply_immediately             = true
    
    tags = merge(var.common-tags, {Name = "${var.common-tags["Environment"]} MySQL Cluster"})
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_rds_cluster_instance" "epm-rds-instances" {

    count                 = 2
    identifier            = "epm-rds-cluster${count.index}"
    cluster_identifier    = aws_rds_cluster.epm-rds-cluster.id
    instance_class        = "db.t2.small"
    db_subnet_group_name  = aws_db_subnet_group.epm-rds-sng.name
    publicly_accessible   = true
    engine                = "aurora-mysql"

    lifecycle {
        create_before_destroy = true
    }

}
resource "aws_db_subnet_group" "epm-rds-sng" {
    name          = "epm-rds-sng"
    description   = "Allowed subnets for Aurora DB cluster instances"
    subnet_ids    = [aws_subnet.epm-pub-net-1.id, aws_subnet.epm-pub-net-2.id]
}
