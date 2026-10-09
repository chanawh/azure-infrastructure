resource "azurerm_resource_group" "this" {
  name     = "rg-network-prod"
  location = "eastus"
}

module "network" {
  source = "../../modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  vnet_name           = "vnet-prod"

  address_space = [
    "10.30.0.0/16"
  ]

  subnets = {
    app = {
      address_prefixes = ["10.30.1.0/24"]
    }

    data = {
      address_prefixes = ["10.30.2.0/24"]
    }
  }
}

output "app_subnet_id" {
  value = module.network.subnet_ids["app"]
}
