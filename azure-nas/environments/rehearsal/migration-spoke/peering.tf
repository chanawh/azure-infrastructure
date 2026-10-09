resource "azurerm_virtual_network_peering" "hub_to_migration" {
  name                      = "peer-hub-to-migration"
  resource_group_name       = data.azurerm_resource_group.hub.name
  virtual_network_name      = data.azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.migration.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "migration_to_hub" {
  name                      = "peer-migration-to-hub"
  resource_group_name       = azurerm_resource_group.migration.name
  virtual_network_name      = azurerm_virtual_network.migration.name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}
