##################################################################################
# PROVIDERS
##################################################################################
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

##################################################################################
# DATA
##################################################################################
data "aws_availability_zones" "available" {}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block           = var.network_block.vpc
  enable_dns_hostnames = true
  tags = local.tags
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = local.tags
}

resource "aws_subnet" "subnet1" {
  cidr_block              = var.network_block.subnet1
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = local.tags
}

resource "aws_subnet" "subnet2" {
  cidr_block              = var.network_block.subnet2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = local.tags
}

# ROUTING #
resource "aws_route_table" "pubrtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = var.network_block.igw
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta-subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.pubrtb.id
  
}

resource "aws_route_table_association" "rta-subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.pubrtb.id
}

# Key Pair#
resource "tls_private_key" "corekey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "tf-asg-key"
  public_key = tls_private_key.corekey.public_key_openssh

  tags = local.tags
}

resource "local_file" "cloud_pem" { 
  filename = "${path.module}/${aws_key_pair.generated_key.key_name}.pem"
  content = tls_private_key.corekey.private_key_pem
}

# Template #
resource "aws_launch_template" "template" {
  name          = "TestTemplate"
  image_id      = "ami-0b89f7b3f054b957e"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.generated_key.key_name
  update_default_version=true

  network_interfaces {
    associate_public_ip_address = true
    security_groups =  [aws_security_group.sg_http.id, aws_security_group.sg_ssh.id] 
  }
    user_data = "${base64encode(local.instance-userdata)}"

  tag_specifications {
    resource_type = "instance"
    tags = local.tags
  }

  tags = local.tags
}

# ALB #
resource "aws_lb" "test_lb" {
  name               = "test-lb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type = "ipv4"

  security_groups    = [aws_security_group.sg_http.id, aws_security_group.sg_ssh.id] 
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  tags = local.tags
}

resource "aws_lb_target_group" "test_target" {
  name     = "test-target"
  target_type   = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path = "/"
    port = 80
  }
  tags = local.tags
}

resource "aws_lb_listener" "test_listener" {
  load_balancer_arn = "${aws_lb.test_lb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.test_target.arn}"
    type             = "forward"
  }
}

resource "aws_autoscaling_group" "test_sg" {
  name = "test-sg"
  launch_template {
    name = aws_launch_template.template.name
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  health_check_grace_period = 120
  desired_capacity   = 2
  max_size           = 4
  min_size           = 2
  target_group_arns = ["${aws_lb_target_group.test_target.arn}"]
}

resource "aws_autoscaling_policy" "test-policy" {
  name                   = "test-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.test_sg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}


# SECURITY GROUPS #
resource "aws_security_group" "sg_http" {
  name   = "sg_http"
  vpc_id = aws_vpc.vpc.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.network_block.http_allow]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.network_block.igw]
  }
  tags = local.tags
}

resource "aws_security_group" "sg_ssh" {
  name   = "sg_ssh"
  vpc_id = aws_vpc.vpc.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.network_block.ssh_allow]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.network_block.igw]
  }
  tags = local.tags
}

output "lb-dns" {
  description = "The DNS of the load balancer."
  value       = aws_lb.test_lb.dns_name
}

output private-key {
  description = "Private Key"
  value       = "${path.module}/${aws_key_pair.generated_key.key_name}.pem"
}
