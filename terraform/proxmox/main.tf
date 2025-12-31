locals {
  all_nodes = concat(
    [for idx, node in var.control_plane_nodes : merge(node, {
      role  = "controller"
      index = idx
    })],
    [for idx, node in var.worker_nodes : merge(node, {
      role  = "worker"
      index = idx + length(var.control_plane_nodes)
    })]
  )

  # Build image URLs from talos_image config
  talos_image_url = "${var.talos_image.factory_url}/image/${var.talos_image.schematic_id}/${var.talos_image.version}/${var.talos_image.platform}-${var.talos_image.arch}.raw.zst"
  talos_image_filename = "talos-${var.talos_image.version}-${var.talos_image.platform}-${var.talos_image.arch}.img"

  # Update image (optional, for preparing upgrades)
  talos_update_url = var.talos_image.update_version != null ? "${var.talos_image.factory_url}/image/${coalesce(var.talos_image.update_schematic_id, var.talos_image.schematic_id)}/${var.talos_image.update_version}/${var.talos_image.platform}-${var.talos_image.arch}.raw.zst" : null
  talos_update_filename = var.talos_image.update_version != null ? "talos-${var.talos_image.update_version}-${var.talos_image.platform}-${var.talos_image.arch}.img" : null
}

# =============================================================================
# MAC Addresses
# =============================================================================
resource "macaddress" "k8s_nodes" {
  for_each = { for node in local.all_nodes : node.name => node }
  prefix   = [188, 36, 17] # BC:24:11 prefix for easy identification
}

# =============================================================================
# Talos Images
# =============================================================================

# Current Talos image
resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.talos_iso_storage
  node_name               = var.proxmox_nodes[0]
  file_name               = local.talos_image_filename
  url                     = local.talos_image_url
  decompression_algorithm = "zst"
  overwrite               = false
}

# Update target image (only created if update_version is set)
resource "proxmox_virtual_environment_download_file" "talos_update_image" {
  count                   = local.talos_update_url != null ? 1 : 0
  content_type            = "iso"
  datastore_id            = var.talos_iso_storage
  node_name               = var.proxmox_nodes[0]
  file_name               = local.talos_update_filename
  url                     = local.talos_update_url
  decompression_algorithm = "zst"
  overwrite               = false
}

# =============================================================================
# Control Plane VMs
# =============================================================================
resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = { for node in var.control_plane_nodes : node.name => node }

  name      = each.value.name
  node_name = each.value.proxmox_node
  vm_id     = var.vm_start_id + index(var.control_plane_nodes, each.value)

  tags = ["kubernetes", "control-plane", "talos"]

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  cpu {
    cores = each.value.vcpus
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  efi_disk {
    datastore_id = each.value.ha_enabled ? var.vm_storage_shared : var.vm_storage_local
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = each.value.ha_enabled ? var.vm_storage_shared : var.vm_storage_local
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = each.value.disk_size
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_image.id
  }

  network_device {
    bridge      = var.vm_network_bridge
    mac_address = upper(macaddress.k8s_nodes[each.key].address)
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.node_gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  serial_device {}

  lifecycle {
    ignore_changes = [started, disk[0].file_id]
  }
}

# =============================================================================
# Worker VMs
# =============================================================================
resource "proxmox_virtual_environment_vm" "worker" {
  for_each = { for node in var.worker_nodes : node.name => node }

  name      = each.value.name
  node_name = each.value.proxmox_node
  vm_id     = var.vm_start_id + length(var.control_plane_nodes) + index(var.worker_nodes, each.value)

  tags = ["kubernetes", "worker", "talos"]

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  cpu {
    cores = each.value.vcpus
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  efi_disk {
    datastore_id = each.value.ha_enabled ? var.vm_storage_shared : var.vm_storage_local
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = each.value.ha_enabled ? var.vm_storage_shared : var.vm_storage_local
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = each.value.disk_size
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_image.id
  }

  network_device {
    bridge      = var.vm_network_bridge
    mac_address = upper(macaddress.k8s_nodes[each.key].address)
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.node_gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  serial_device {}

  lifecycle {
    ignore_changes = [started, disk[0].file_id]
  }
}

# =============================================================================
# Generated Files
# =============================================================================
resource "local_file" "nodes_yaml" {
  content = templatefile("${path.module}/templates/nodes.yaml.tftpl", {
    control_plane_nodes = [for node in var.control_plane_nodes : {
      name     = node.name
      address  = node.ip_address
      mac_addr = upper(macaddress.k8s_nodes[node.name].address)
    }]
    worker_nodes = [for node in var.worker_nodes : {
      name     = node.name
      address  = node.ip_address
      mac_addr = upper(macaddress.k8s_nodes[node.name].address)
    }]
    schematic_id = var.talos_image.schematic_id
  })
  filename = "${path.module}/../../nodes.yaml"
}
