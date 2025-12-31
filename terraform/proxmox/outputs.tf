output "control_plane_nodes" {
  description = "Control plane node details"
  value = [for node in var.control_plane_nodes : {
    name       = node.name
    address    = node.ip_address
    controller = true
    mac_addr   = upper(macaddress.k8s_nodes[node.name].address)
  }]
}

output "worker_nodes" {
  description = "Worker node details"
  value = [for node in var.worker_nodes : {
    name       = node.name
    address    = node.ip_address
    controller = false
    mac_addr   = upper(macaddress.k8s_nodes[node.name].address)
  }]
}

output "mac_addresses" {
  description = "MAC addresses for all nodes (for nodes.yaml)"
  value = { for name, mac in macaddress.k8s_nodes : name => upper(mac.address) }
}

output "vm_ids" {
  description = "Proxmox VM IDs"
  value = merge(
    { for name, vm in proxmox_virtual_environment_vm.control_plane : name => vm.vm_id },
    { for name, vm in proxmox_virtual_environment_vm.worker : name => vm.vm_id }
  )
}

output "talos_image" {
  description = "Talos image info"
  value = {
    version  = var.talos_image.version
    file_id  = proxmox_virtual_environment_download_file.talos_image.id
    filename = local.talos_image_filename
  }
}

output "talos_schematic_id" {
  description = "Talos schematic ID (for nodes.yaml)"
  value = var.talos_image.schematic_id
}

output "cluster_api_addr" {
  description = "Recommended cluster API address (VIP)"
  value       = "192.168.20.10"
}
