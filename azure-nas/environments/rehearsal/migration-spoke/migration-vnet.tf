resource "azurerm_virtual_network" "migration" {
  name                = "vnet-${var.prefix}-${var.environment}-migration"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  address_space       = ["10.51.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "migration_vms" {
  name                 = "snet-migration-vms"
  resource_group_name  = azurerm_resource_group.migration.name
  virtual_network_name = azurerm_virtual_network.migration.name
  address_prefixes     = ["10.51.10.0/24"]
}

resource "azurerm_subnet" "rehearsal_nodes" {
  name                 = "snet-rehearsal-nodes"
  resource_group_name  = azurerm_resource_group.migration.name
  virtual_network_name = azurerm_virtual_network.migration.name
  address_prefixes     = ["10.51.20.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-migration-private-endpoints"
  resource_group_name  = azurerm_resource_group.migration.name
  virtual_network_name = azurerm_virtual_network.migration.name
  address_prefixes     = ["10.51.30.0/24"]

  private_endpoint_network_policies = "Disabled"
}
