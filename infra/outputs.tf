output "boxes" {
  description = "Public IPs, for admin SSH: ssh ubuntu@<ip>"
  value       = { for name, box in module.customer : name => box.public_ip }
}
