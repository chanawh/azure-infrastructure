#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${1:?Pass resource group name}"
VNET_NAME="${2:?Pass hub VNet name}"

echo "Checking hub VNet address space..."
CIDR="$(az network vnet show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --query "addressSpace.addressPrefixes[0]" \
  --output tsv)"

test "$CIDR" = "10.50.0.0/16"
echo "PASS: Hub VNet CIDR is $CIDR"

check_subnet() {
  local subnet_name="$1"
  local expected_cidr="$2"

  actual_cidr="$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$subnet_name" \
    --query "addressPrefix" \
    --output tsv)"

  test "$actual_cidr" = "$expected_cidr"
  echo "PASS: $subnet_name is $actual_cidr"
}

check_subnet "AzureFirewallSubnet" "10.50.0.0/26"
check_subnet "AzureBastionSubnet" "10.50.0.64/26"
check_subnet "GatewaySubnet" "10.50.1.0/27"
check_subnet "snet-dns-resolver" "10.50.2.0/27"
check_subnet "snet-hub-test" "10.50.10.0/24"

echo "PASS: Hub network structure matches the expected design."
