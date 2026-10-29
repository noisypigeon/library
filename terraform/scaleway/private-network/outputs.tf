output "id" {
  description = "Private Network ID"
  value       = scaleway_vpc_private_network.this.id
}

output "name" {
  description = "Private Network name"
  value       = scaleway_vpc_private_network.this.name
}
