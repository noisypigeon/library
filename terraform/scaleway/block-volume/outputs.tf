output "id" {
  description = "Volume ID"
  value       = scaleway_block_volume.volume.id
}

output "name" {
  description = "Computed volume name"
  value       = scaleway_block_volume.volume.name
}
