data "azurerm_resource_group" "hub" {
  name = var.hub_resource_group_name
}

data "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  resource_group_name = data.azurerm_resource_group.hub.name
}

data "azurerm_subnet" "hub_test" {
  name                 = "snet-hub-test"
  virtual_network_name = data.azurerm_virtual_network.hub.name
  resource_group_name  = data.azurerm_resource_group.hub.name
}

resource "azurerm_resource_group" "migration" {
  name     = var.migration_resource_group_name
  location = var.location
  tags     = var.tags
}
