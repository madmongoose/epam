//variable "aws_access_key" {}
//variable "aws_secret_key" {}
variable "generated_key_name" {
  type        = string
  //default     = "terraform-key-pair"
  description = "Key-pair generated by Terraform"
}
variable "name" {
  default = "admin"
}

variable "common-tags" {
  description = "Common Tags to apply to all resources"
  type = map
  default = {
      Owner = "Roman Gorokhovsky"
      Project = "Epam"
      Environment = "Prod"
  }
}