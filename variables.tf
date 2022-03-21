variable "your_region" {
  type        = string
  description = "Where you want your server to be. The options are here https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html."
}

variable "your_public_key" {
  type        = string
  description = "This will be in ~/.ssh/id_rsa.pub by default."
}

variable "aws_access_key" {
  type = string
}

variable "aws_secret_key" {
  type = string
}

variable "mc_root" {
  description = "Where to install minecraft on your instance"
  type        = string
  default     = "/home/minecraft"
}

variable "mc_version" {
  description = "Which version of minecraft to install"
  type        = string
  default     = "latest"
}

variable "mc_type" {
  description = "Type of minecraft distribution - snapshot or release"
  type        = string
  default     = "release"
}

variable "mc_backup_freq" {
  description = "How often (mins) to sync to S3"
  type        = number
  default     = 5
}


// You'll want to tune these next two based on the instance type
variable "java_ms_mem" {
  description = "Java initial and minimum heap size"
  type        = string
  default     = "1G"
}

variable "java_mx_mem" {
  description = "Java maximum heap size"
  type        = string
  default     = "1G"
}
