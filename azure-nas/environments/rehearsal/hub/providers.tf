provider "azurerm" {
  features {}

  # Stops Terraform from trying to register many unrelated Azure providers.
  resource_provider_registrations = "none"
}
