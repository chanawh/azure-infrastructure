output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.hub.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.hub.location
}

output "vnet_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "vnet_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "vnet_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value = {
    firewall     = azurerm_subnet.firewall.id
    bastion      = azurerm_subnet.bastion.id
    gateway      = azurerm_subnet.gateway.id
    dns_resolver = azurerm_subnet.dns_resolver.id
    hub_test     = azurerm_subnet.hub_test.id
  }
}

output "hub_test_vm_name" {
  description = "Name of the hub test VM"
  value       = azurerm_linux_virtual_machine.hub_test.name
}

output "hub_test_vm_private_ip" {
  description = "Private IP address of the hub test VM"
  value       = azurerm_network_interface.hub_test.private_ip_address
}
