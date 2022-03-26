provider "aws" {
  profile    = "private"
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

module "minecraft_server" {
  source          = "./minecraft_server"
  name            = "libradacraft"
  your_public_key = var.your_public_key
  aws_region      = var.aws_region
}
