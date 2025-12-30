# =============================================================================
# Proxmox Connection
# =============================================================================
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in format 'user@realm!tokenid=secret'"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

# =============================================================================
# Proxmox Cluster
# =============================================================================
variable "proxmox_nodes" {
  description = "List of Proxmox node names"
  type        = list(string)
  default     = ["yggdrasil01", "yggdrasil02", "yggdrasil03", "yggdrasil04", "yggdrasil05"]
}

# =============================================================================
# Talos Image Configuration
# =============================================================================
variable "talos_image" {
  description = "Talos image configuration"
  type = object({
    factory_url      = optional(string, "https://factory.talos.dev")
    schematic_id     = string
    version          = string
    update_schematic_id = optional(string)  # For preparing upgrades
    update_version      = optional(string)  # For preparing upgrades
    arch             = optional(string, "amd64")
    platform         = optional(string, "nocloud")
  })
}

variable "talos_iso_storage" {
  description = "Proxmox storage for Talos images"
  type        = string
  default     = "cephfs_shared"
}

# =============================================================================
# VM Storage
# =============================================================================
variable "vm_storage_local" {
  description = "Proxmox local storage for non-HA VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_storage_shared" {
  description = "Proxmox shared storage for HA VM disks (Ceph)"
  type        = string
  default     = "ceph-pool"
}

# =============================================================================
# VM Networking
# =============================================================================
variable "vm_network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

variable "vm_vlan_tag" {
  description = "VLAN tag for the VM network (set to null if not using VLANs)"
  type        = number
  default     = null
}

variable "node_gateway" {
  description = "Gateway IP for K8s nodes"
  type        = string
  default     = "192.168.20.1"
}

variable "dns_servers" {
  description = "DNS servers for nodes"
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

# =============================================================================
# Control Plane Nodes
# =============================================================================
variable "control_plane_nodes" {
  description = "Control plane node configuration"
  type = list(object({
    name         = string
    ip_address   = string
    proxmox_node = string
    vcpus        = optional(number, 4)
    memory       = optional(number, 8192)
    disk_size    = optional(number, 50)
    ha_enabled   = optional(bool, false)
    ha_group     = optional(string, null)
  }))
  default = [
    # HA control plane - can migrate between 64GB hosts
    {
      name         = "k8s-cp-1"
      ip_address   = "192.168.20.40"
      proxmox_node = "yggdrasil01"
      ha_enabled   = true
      ha_group     = "ha-64gb"
    },
    # Fixed control planes on 32GB hosts
    { name = "k8s-cp-2", ip_address = "192.168.20.41", proxmox_node = "yggdrasil04" },
    { name = "k8s-cp-3", ip_address = "192.168.20.42", proxmox_node = "yggdrasil05" },
  ]
}

# =============================================================================
# Worker Nodes
# =============================================================================
variable "worker_nodes" {
  description = "Worker node configuration"
  type = list(object({
    name         = string
    ip_address   = string
    proxmox_node = string
    vcpus        = optional(number, 12)
    memory       = optional(number, 40960)  # 40GB
    disk_size    = optional(number, 50)     # Small - Ceph for persistent storage
    ha_enabled   = optional(bool, false)
    ha_group     = optional(string, null)
  }))
  default = [
    # Workers on 64GB hosts
    { name = "k8s-worker-1", ip_address = "192.168.20.50", proxmox_node = "yggdrasil01" },
    { name = "k8s-worker-2", ip_address = "192.168.20.51", proxmox_node = "yggdrasil02" },
    { name = "k8s-worker-3", ip_address = "192.168.20.52", proxmox_node = "yggdrasil03" },
  ]
}

# =============================================================================
# VM IDs
# =============================================================================
variable "vm_start_id" {
  description = "Starting VM ID"
  type        = number
  default     = 200
}
