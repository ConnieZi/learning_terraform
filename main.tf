data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

# use the vpc module from the terraform registry instead of writing our own
module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# (deprecated) set up a security group for our EC2 instance
# 1. set up a vpc, which is the network infra provided by Amazon
data "aws_vpc" "default" {
  default = true
}

# resource "aws_instance" "blog" {
#   ami           = data.aws_ami.app_ami.id
#   instance_type = var.instance_type

#   # look for the output of this module in the documentation outputs section
#   vpc_security_group_ids = [module.blog_sg.security_group_id]

#   tags = {
#     Name = "LearningTerraform"
#   }
# }

# this will late replace the above aws_instance resource and autoscale the EC2 instances
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.10.0"
  
  name     = "blog"
  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   =  module.blog_alb.target_group_arns  # target group is created by the load balancer, it's what the traffic is targeted to
  security_groups     = [module.blog_sg.security_group_id]

  image_id       = data.aws_ami.app_ami.id
  instance_type  = var.instance_type
}

# Application Load Balancer
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "blog-alb"

  load_balancer_type = "application"

  vpc_id           = module.blog_vpc.vpc_id
  subnets          = module.blog_vpc.public_subnets
  security_groups  = [module.blog_sg.security_group_id]

  target_groups = [
    {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      # NOTE: no more targets here as we specify them in autoscaling module
      # targets = {
      #   my_target = {
      #     target_id = aws_instance.blog.id  # this tells load balancer to send traffic to this instance
      #     port = 80
      #   }
      # }
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "Dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.0.0"
  name    = "blog_new"

  # The vpc we set up above
  vpc_id = module.blog_vpc.public_subnets[0] # just use the first public subnet

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}




# Deprecated below
# 2. set up a security group, which is a firewall for EC2 instances
resource "aws_security_group" "blog" {
  name        = "blog"
  description = "Allow http and https in. Allow everything out"

  # The vpc we set up above
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "blog_http_in" {
  type        = "ingress"  # this is because we are setting up inbound rules
  from_port   = 80    # port 80 is for http
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # which networks we want to allow access on, and here it's a wide-open public website

  security_group_id = aws_security_group.blog.id
}

resource "aws_security_group_rule" "blog_https_in" {
  type        = "ingress"  # this is because we are setting up inbound rules
  from_port   = 443    # port 80 is for http
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # which networks we want to allow access on, and here it's a wide-open public website

  security_group_id = aws_security_group.blog.id
}

resource "aws_security_group_rule" "blog_everything_out" {
  type        = "egress"  # this is because we are setting up inbound rules
  from_port   = 00        # allow everything outbound
  to_port     = 00
  protocol    = "-1"      # allow all protocols
  cidr_blocks = ["0.0.0.0/0"]  # which networks we want to allow access on, and here it's a wide-open public website

  security_group_id = aws_security_group.blog.id
}
