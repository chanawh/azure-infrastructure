#!/usr/bin/env bash
set -euo pipefail

HUB_RG="${1:?Pass the Hub resource group name}"
HUB_VM="${2:?Pass the Hub test VM name}"
MIGRATION_RG="${3:?Pass the Migration resource group name}"
MIGRATION_VM="${4:?Pass the Migration test VM name}"

HUB_VNET="vnet-nasrehearsal-lab-hub"
MIGRATION_VNET="vnet-nasrehearsal-lab-migration"

HUB_IP="$(az vm show \
  --resource-group "$HUB_RG" \
  --name "$HUB_VM" \
  --show-details \
  --query "privateIps" \
  --output tsv)"

MIGRATION_IP="$(az vm show \
  --resource-group "$MIGRATION_RG" \
  --name "$MIGRATION_VM" \
  --show-details \
  --query "privateIps" \
  --output tsv)"

MIGRATION_PUBLIC_IP="$(az vm show \
  --resource-group "$MIGRATION_RG" \
  --name "$MIGRATION_VM" \
  --show-details \
  --query "publicIps" \
  --output tsv)"

HUB_PEERING_STATE="$(az network vnet peering show \
  --resource-group "$HUB_RG" \
  --vnet-name "$HUB_VNET" \
  --name "peer-hub-to-migration" \
  --query "peeringState" \
  --output tsv)"

MIGRATION_PEERING_STATE="$(az network vnet peering show \
  --resource-group "$MIGRATION_RG" \
  --vnet-name "$MIGRATION_VNET" \
  --name "peer-migration-to-hub" \
  --query "peeringState" \
  --output tsv)"

echo "Hub test VM IP:       $HUB_IP"
echo "Migration test VM IP: $MIGRATION_IP"

test "$HUB_PEERING_STATE" = "Connected"
echo "PASS: Hub-to-Migration peering is Connected."

test "$MIGRATION_PEERING_STATE" = "Connected"
echo "PASS: Migration-to-Hub peering is Connected."

test -z "$MIGRATION_PUBLIC_IP"
echo "PASS: Migration test VM has no public IP."

echo "Testing Hub VM → Migration VM TCP/22..."

az vm run-command invoke \
  --resource-group "$HUB_RG" \
  --name "$HUB_VM" \
  --command-id RunShellScript \
  --scripts "timeout 5 bash -c '</dev/tcp/${MIGRATION_IP}/22' && echo PASS || exit 1" \
  --query "value[0].message" \
  --output tsv

echo "PASS: Hub VM reached Migration VM on TCP/22."

echo "Testing Migration VM → Hub VM TCP/22..."

az vm run-command invoke \
  --resource-group "$MIGRATION_RG" \
  --name "$MIGRATION_VM" \
  --command-id RunShellScript \
  --scripts "timeout 5 bash -c '</dev/tcp/${HUB_IP}/22' && echo PASS || exit 1" \
  --query "value[0].message" \
  --output tsv

echo "PASS: Migration VM reached Hub VM on TCP/22."
