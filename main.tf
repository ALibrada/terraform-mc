terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.6.0"
    }
  }
}

provider "aws" {
  profile    = "private"
  region     = var.your_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

data "aws_caller_identity" "aws" {}

locals {
  name = "libradacraft"
  tf_tags = {
    Name      = "Minecraft"
    Terraform = true,
    By        = data.aws_caller_identity.aws.arn
  }
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "aws_security_group" "minecraft" {
  ingress {
    description = "Receive SSH from home."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }
  ingress {
    description = "Receive Minecraft from everywhere."
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Send everywhere."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tf_tags
}

// S3 bucket for persisting minecraft
resource "random_string" "s3" {
  length  = 12
  special = false
  upper   = false
}

locals {
  bucket = "${local.name}-${random_string.s3.result}"
}

resource "aws_s3_bucket" "minecraft-backup" {
  bucket = local.bucket
  tags   = local.tf_tags
}

resource "aws_s3_bucket_acl" "minecraft-bucket_acl" {
  bucket = aws_s3_bucket.minecraft-backup.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "minecraft-bucket_versioning" {
  bucket = aws_s3_bucket.minecraft-backup.id
  versioning_configuration {
    status = "Disabled"
  }
}

// IAM role for S3 access
resource "aws_iam_role" "allow_s3" {
  name               = "${local.name}-allow-ec2-to-s3"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "mc" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.allow_s3.name
}

resource "aws_iam_role_policy" "mc_allow_ec2_to_s3" {
  name   = "${local.name}-allow-ec2-to-s3"
  role   = aws_iam_role.allow_s3.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${local.bucket}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::${local.bucket}/*"]
    }
  ]
}
EOF
}

resource "aws_key_pair" "home" {
  key_name   = "Home"
  public_key = var.your_public_key
  tags       = local.tf_tags
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    mc_root        = var.mc_root
    java_mx_mem    = var.java_mx_mem
    java_ms_mem    = var.java_ms_mem
    mc_version     = var.mc_version
    mc_type        = var.mc_type
    mc_bucket      = local.bucket
    mc_backup_freq = var.mc_backup_freq
  }
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.amazon-linux-2.image_id
  instance_type               = "t2.small"
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.home.key_name
  user_data                   = data.template_file.user_data.rendered
  iam_instance_profile        = aws_iam_instance_profile.mc.id
  tags                        = local.tf_tags
}

output "instance_ip_addr" {
  value = aws_instance.minecraft.public_ip
}
