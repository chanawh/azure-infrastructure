output "migration_resource_group_name" {
  value = azurerm_resource_group.migration.name
}

output "migration_vnet_name" {
  value = azurerm_virtual_network.migration.name
}

output "migration_vnet_id" {
  value = azurerm_virtual_network.migration.id
}

output "migration_subnet_ids" {
  value = {
    migration_vms     = azurerm_subnet.migration_vms.id
    rehearsal_nodes   = azurerm_subnet.rehearsal_nodes.id
    private_endpoints = azurerm_subnet.private_endpoints.id
  }
}

output "migration_test_vm_name" {
  value = azurerm_linux_virtual_machine.migration_test.name
}

output "migration_test_vm_private_ip" {
  value = azurerm_network_interface.migration_test.private_ip_address
}
