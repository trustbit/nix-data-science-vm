terraform {

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.78.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 3.78.0"
    }
  }
}

provider "google" {
  project     = var.project
  region      = var.region
  zone        = var.zone
}

provider "google-beta" {
  project     = var.project
  region      = var.region
  zone        = var.zone
}

resource "google_project_service" "services" {
  for_each = toset(var.services)
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}

data "template_file" "nix_cloud_init" {
  template = file("${path.root}/cloud-init.tpl")

  vars = {
    domain_name = "${local.domain_name}"
  }

}

resource "google_compute_firewall" "allow-web" {
  name    = "workspace-access"
  network = "default"

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "22"]
  }

  source_tags = ["workspace"]

  depends_on = [
    google_project_service.services
  ]
}

resource "google_compute_address" "workspace-static-ip" {
  name = "workspace-static-ip"
}

data "google_compute_default_service_account" "default" {
}

resource "google_compute_instance" "vscode" {
  name                = "workspace"
  deletion_protection = "false"
  enable_display      = "true"
  machine_type         = var.vm_size

  tags = ["workspace"]

  boot_disk {
    initialize_params {
      image = var.os_image
    }
  }

  allow_stopping_for_update = true

  can_ip_forward = "false"

  confidential_instance_config {
    enable_confidential_compute = "false"
  }

  network_interface {
    network    = "default"
    access_config {
      nat_ip = google_compute_address.workspace-static-ip.address
    }
  }

#  attached_disk {
#    source      = "workspace-data"
#    device_name = "workspace-data"
#  }
  
  metadata = {
    ssh-keys = "eugene:${file(pathexpand("~/.ssh/id_rsa.pub"))}"
#    user-data = data.template_file.nix_cloud_init.rendered
    enable-oslogin: "TRUE"
    serial-port-logging-enable = "TRUE"
  }

  metadata_startup_script = data.template_file.nix_cloud_init.rendered

  service_account {
    email  = data.google_compute_default_service_account.default.email
    scopes = ["storage-full", "logging-write", "monitoring-write", "pubsub", "service-management", "service-control", "trace", "cloud-platform", "bigquery", "datastore"]
  }

  depends_on = [
    data.template_file.nix_cloud_init,
    google_project_service.services
  ]
}

data "template_file" "endpoint" {
  depends_on = [google_project_service.services]
  template   = file("${path.root}/endpoint.tpl")
  vars = {
    title       = "DSP workspace"
    description = "DSP workspace"
    ip_address  = google_compute_address.workspace-static-ip.address
    domain_name = "${local.domain_name}"
  }
}

resource "google_endpoints_service" "telemetry_openapi_service" {
  service_name   = local.domain_name
  openapi_config = data.template_file.endpoint.rendered

  depends_on = [
    data.template_file.endpoint,
    google_project_service.services
  ]
}
