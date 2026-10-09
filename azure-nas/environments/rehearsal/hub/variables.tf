variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., rehearsal, production)"
  type        = string
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the Linux administrator. Pass through TF_VAR_admin_ssh_public_key."
  type        = string
}

variable "vm_size" {
  description = "VM size for test VMs"
  type        = string
  default     = "Standard_D2als_v7"
}

variable "tags" {
  type = map(string)

  default = {
    Project     = "nas-to-azure"
    Environment = "lab"
    ManagedBy   = "terraform"
    Purpose     = "hub-functional-test"
  }
}
