# Input Variable
variable "aws_access_key" {
  type = string
  description = "access key"
}

variable "aws_secret_key" {
  type = string
  description = "secret key"
  sensitive = true
}

variable "aws_region" {
  type = string
  description = "region"
  default = "ap-southeast-1"
}

variable "network_block" {
  type = map(string)
  default = {
    vpc = "10.0.0.0/16"
    subnet1 = "10.0.10.0/24"
    subnet2 = "10.0.20.0/24"
    igw = "0.0.0.0/0"
    http_allow = "0.0.0.0/0"
    ssh_allow = "0.0.0.0/0"
  }
}
