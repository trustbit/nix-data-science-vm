variable "project" {
  default = "softwarepark-sandbox"
  type = string
}

variable "region" {
  default = "europe-west4"
  type = string
}

variable "email" {
  default = "krasina15@gmail.com"
  type = string
}

variable services {
  type        = list
  default     = [
    "compute.googleapis.com",
    "serviceusage.googleapis.com",
    "servicemanagement.googleapis.com",
    "compute.googleapis.com",
    "networkmanagement.googleapis.com"
  ]
}

variable "zone" {
  default = "europe-west4-a"
  type = string
}

variable "os_image" {
  default = "debian-11"
  type    = string
}

variable "vm_size" {
  default = "e2-medium"
  type    = string
}

locals {
  domain_name = "workspace.endpoints.${var.project}.cloud.goog"
}
