terraform {
  required_providers {
    openstack = { source = "terraform-provider-openstack/openstack" }
    google    = { source = "hashicorp/google" }
    mailgun   = { source = "wgebis/mailgun" }
    random    = { source = "hashicorp/random" }
  }
}

# --- backups: a bucket the box can write and read but never delete from.
# The 30-day retention policy is the real backstop — even leaked keys can't
# destroy history younger than that.

resource "google_storage_bucket" "backups" {
  name                        = "appsmoothly-${var.name}"
  location                    = var.gcs_location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  retention_policy {
    retention_period = 30 * 24 * 3600
  }

  soft_delete_policy {
    retention_duration_seconds = 30 * 24 * 3600
  }

  # nightly code bundles + box-state tars (backup-code cron on the box) —
  # drop them once the retention policy no longer protects them
  lifecycle_rule {
    condition {
      age            = 60
      matches_prefix = ["code/", "box/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "backup" {
  account_id   = "appsmoothly-${var.name}"
  display_name = "appsmoothly ${var.name} backups (scoped to its bucket only)"
}

resource "google_storage_bucket_iam_member" "creator" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.backup.email}"
}

resource "google_storage_bucket_iam_member" "viewer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backup.email}"
}

# S3-interoperability key — litestream and Active Storage speak S3.
resource "google_storage_hmac_key" "backup" {
  service_account_email = google_service_account.backup.email
}

# --- email: per-customer Mailgun sending domain + SMTP credential.
# Used by Authelia (sign-in mails), the factory (forwarding captured mails),
# and the customer's live app (Action Mailer via SMTP_* env).

# dkim_selector is pinned so the DNS record names are known at plan time;
# 1024-bit key keeps the DKIM TXT value inside a single 255-char string.
resource "mailgun_domain" "mail" {
  name          = "mail.${var.domain}"
  region        = "eu"
  spam_action   = "disabled"
  dkim_selector = "mg"
}

resource "random_password" "smtp" {
  length  = 24
  special = false
}

resource "mailgun_domain_credential" "app" {
  domain   = mailgun_domain.mail.name
  login    = "app"
  password = random_password.smtp.result
  region   = "eu"
}

# --- DNS: everything automatic in the Designate zone.

resource "openstack_dns_recordset_v2" "app" {
  zone_id = var.zone_id
  name    = "${var.domain}."
  type    = "A"
  ttl     = 300
  records = [openstack_compute_instance_v2.box.access_ip_v4]
}

resource "openstack_dns_recordset_v2" "wildcard" {
  zone_id = var.zone_id
  name    = "*.${var.domain}."
  type    = "A"
  ttl     = 300
  records = [openstack_compute_instance_v2.box.access_ip_v4]
}

resource "openstack_dns_recordset_v2" "spf" {
  zone_id = var.zone_id
  name    = "mail.${var.domain}."
  type    = "TXT"
  ttl     = 300
  records = ["\"v=spf1 include:mailgun.org ~all\""]
}

resource "openstack_dns_recordset_v2" "dkim" {
  zone_id = var.zone_id
  name    = "mg._domainkey.mail.${var.domain}."
  type    = "TXT"
  ttl     = 300
  records = [for r in mailgun_domain.mail.sending_records_set :
    "\"${r.value}\"" if strcontains(r.name, "_domainkey")
  ]
}

resource "openstack_dns_recordset_v2" "tracking" {
  zone_id = var.zone_id
  name    = "email.mail.${var.domain}."
  type    = "CNAME"
  ttl     = 300
  records = ["eu.mailgun.org."]
}

# --- network: 80/443 to the world, 22 to the admin, nothing else.

resource "openstack_networking_secgroup_v2" "box" {
  name                 = "appsmoothly-${var.name}"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.box.id
}

resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.box.id
}

resource "openstack_networking_secgroup_rule_v2" "ssh_admin" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.box.id
}

resource "openstack_networking_secgroup_rule_v2" "egress_v4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.box.id
}

resource "openstack_networking_secgroup_rule_v2" "egress_v6" {
  direction         = "egress"
  ethertype         = "IPv6"
  security_group_id = openstack_networking_secgroup_v2.box.id
}

# --- the box itself; cloud-init builds the whole stack on first boot.

resource "openstack_compute_instance_v2" "box" {
  name            = "appsmoothly-${var.name}"
  image_name      = var.image
  flavor_name     = var.flavor
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.box.name]

  network {
    name = var.network
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    customer             = var.name
    domain               = var.domain
    admin_email          = var.admin_email
    factory_repo         = var.factory_repo
    s3_bucket            = google_storage_bucket.backups.name
    s3_region            = lower(var.gcs_location)
    s3_access_key_id     = google_storage_hmac_key.backup.access_id
    s3_secret_access_key = google_storage_hmac_key.backup.secret
    smtp_password        = random_password.smtp.result
  })
}
