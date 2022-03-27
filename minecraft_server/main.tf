data "aws_caller_identity" "aws" {}
data "aws_region" "current" {}

locals {
  name = var.name
  tf_tags = {
    Name      = "Minecraft - ${var.name}"
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
resource "random_string" "name" {
  length  = 12
  special = false
  upper   = false
}

locals {
  bucket = "${local.name}-${random_string.name.result}"
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

data "template_file" "instance-policy" {
  template = file("${path.module}/policies/instance-policy.json")
  vars = {
    mc_bucket = local.bucket
  }
}

// IAM role for S3 access
resource "aws_iam_role" "allow_s3" {
  name               = "${local.name}-allow-ec2-to-s3"
  assume_role_policy = file("${path.module}/policies/instance-role.json")
}

resource "aws_iam_instance_profile" "mc" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.allow_s3.name
}

resource "aws_iam_role_policy" "mc_allow_ec2_to_s3" {
  name   = "${local.name}-allow-ec2-to-s3"
  role   = aws_iam_role.allow_s3.id
  policy = data.template_file.instance-policy.rendered
}

resource "aws_key_pair" "home" {
  key_name   = "Home"
  public_key = var.your_public_key
  tags       = local.tf_tags
}

data "template_file" "service" {
  template = file("${path.module}/files/minecraft.service")
  vars = {
    mc_root     = var.mc_root
    java_mx_mem = var.java_mx_mem
    java_ms_mem = var.java_ms_mem
  }
}

data "template_file" "cron" {
  template = file("${path.module}/files/minecraft-backup.cron")
  vars = {
    mc_backup_freq = var.mc_backup_freq
    mc_root        = var.mc_root
  }
}

module "minecraft_version" {
  source            = "github.com/ALibrada/terraform-minecraft-version.git?ref=main"
  minecraft_version = var.mc_version
}

resource "random_string" "restic" {
  length  = 12
  special = false
  upper   = false
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    minecraft-service           = base64encode(data.template_file.service.rendered)
    minecraft-cron              = base64encode(data.template_file.cron.rendered)
    mc_root                     = var.mc_root
    server_url                  = module.minecraft_version.download_link
    bucket_regional_domain_name = aws_s3_bucket.minecraft-backup.bucket_regional_domain_name
    aws_region                  = data.aws_region.current.name
    restic_password             = random_string.restic.result
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
  instance_type               = "t3.small"
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.home.key_name
  user_data                   = data.template_file.user_data.rendered
  iam_instance_profile        = aws_iam_instance_profile.mc.id
  tags                        = local.tf_tags
}
