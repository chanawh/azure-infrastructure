variable "subscription_id" {
  description = "Azure subscription ID used for this rehearsal environment."
  type        = string
  sensitive   = true
}

variable "hub_resource_group_name" {
  description = "Existing resource group containing the Hub VNet."
  type        = string
  default     = "rg-nasrehearsal-lab-hub"
}

variable "hub_vnet_name" {
  description = "Existing Hub VNet name."
  type        = string
  default     = "vnet-nasrehearsal-lab-hub"
}

variable "hub_test_vm_name" {
  description = "Hub test VM name. It must exist before bidirectional functional tests."
  type        = string
  default     = "vm-nasrehearsal-lab-hub-test"
}

variable "migration_resource_group_name" {
  description = "Resource group created for the Migration Spoke."
  type        = string
  default     = "rg-nasrehearsal-lab-migration"
}

variable "location" {
  description = "Azure region. Keep it aligned with the Hub VNet region."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  type    = string
  default = "nasrehearsal"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "admin_username" {
  description = "Linux administrator username for the test VM."
  type        = string
  default     = "azureadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the Linux administrator. Pass through TF_VAR_admin_ssh_public_key."
  type        = string
}

variable "vm_size" {
  description = "Small VM size for rehearsal functional testing."
  type        = string
  default     = "Standard_B1s"
}

variable "tags" {
  type = map(string)

  default = {
    Project     = "nas-to-azure"
    Environment = "lab"
    ManagedBy   = "terraform"
    Purpose     = "migration-spoke-functional-test"
  }
}
