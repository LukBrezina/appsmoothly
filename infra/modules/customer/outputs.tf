output "public_ip" {
  value = openstack_compute_instance_v2.box.access_ip_v4
}
