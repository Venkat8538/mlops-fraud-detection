variable "vpc_id" {
  description = "VPC ID to launch Airflow EC2 into"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for Airflow EC2"
  type        = string
}

variable "allowed_cidr" {
  description = "Your IP CIDR for SSH and Airflow UI access (e.g. 1.2.3.4/32)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content for EC2 access"
  type        = string
}
