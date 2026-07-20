# appsmoothly.com — one VPS per customer. Drive it with the wrapper script:
#   infra/customer up <name> <admin-email>     infra/customer down <name>
# All credentials come from infra/.env (see .env.example); the script sources
# it and manages the `customers` map in customers.auto.tfvars.json.
# Runs from your laptop only — fleet credentials never live on customer boxes.

terraform {
  required_version = ">= 1.6"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # One-time bootstrap (state can't create its own bucket — see infra/README.md):
  #   gcloud storage buckets create gs://appsmoothly-tofu-state --location=europe-west6 --uniform-bucket-level-access
  #   gcloud storage buckets update gs://appsmoothly-tofu-state --versioning
  backend "gcs" {
    bucket = "appsmoothly-tofu-state"
    prefix = "appsmoothly"
  }
}

provider "openstack" {}

provider "google" {
  project = var.gcp_project
}

provider "mailgun" {}

resource "openstack_compute_keypair_v2" "admin" {
  name       = "appsmoothly-admin"
  public_key = var.admin_ssh_pubkey
}

# The appsmoothly.com zone lives in Designate (Infomaniak DNSaaS). One-time
# manual step ever: at the domain registrar, set appsmoothly.com's nameservers
# to the ones Designate assigns this zone
# (visible after first apply via: openstack recordset list appsmoothly.com.)
resource "openstack_dns_zone_v2" "apps" {
  name  = "${var.zone}."
  email = var.zone_email
  ttl   = 300
}

module "customer" {
  source   = "./modules/customer"
  for_each = var.customers

  name         = each.key
  domain       = "${each.key}.${var.zone}"
  zone_id      = openstack_dns_zone_v2.apps.id
  admin_email  = each.value.admin_email
  admin_cidr   = var.admin_cidr
  keypair      = openstack_compute_keypair_v2.admin.name
  flavor       = var.flavor
  image        = var.image
  network      = var.network
  gcs_location = var.gcs_location
  factory_repo = var.factory_repo
}
