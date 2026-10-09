variable "resource_group_name" {
  description = "Resource group where the VNet is created."
  type        = string
}

variable "location" {
  description = "Azure region for the VNet."
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network."
  type        = string
}

variable "address_space" {
  description = "CIDR ranges for the virtual network."
  type        = list(string)

  validation {
    condition = alltrue([
      for cidr in var.address_space : can(cidrhost(cidr, 0))
    ])

    error_message = "Every address_space entry must be a valid CIDR, such as 10.20.0.0/16."
  }
}

variable "subnets" {
  description = "Subnets keyed by stable consumer-facing names."

  type = map(object({
    address_prefixes = list(string)
  }))

  validation {
    condition = alltrue(flatten([
      for subnet in values(var.subnets) : [
        for cidr in subnet.address_prefixes : can(cidrhost(cidr, 0))
      ]
    ]))

    error_message = "Every subnet address prefix must be a valid CIDR, such as 10.20.1.0/24."
  }
}
