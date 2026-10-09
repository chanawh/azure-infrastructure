# Migration Spoke Deployment - Complete Documentation

This document describes the Migration Spoke infrastructure deployment, including all resources, issues encountered, resolutions, and validation results.

## Overview

The Migration Spoke is a separate VNet that peered with the Hub VNet to test private network connectivity between VNets. This validates the foundation for NAS migration operations.

## Deployment Status

✅ **DEPLOYED AND VALIDATED** - October 7, 2026

## What Was Built

### Resource Group
- **Name**: `rg-nasrehearsal-lab-migration`
- **Location**: `eastus`
- **State**: Succeeded
- **Tags**:
  - Project: nas-to-azure
  - Environment: lab
  - ManagedBy: terraform
  - Purpose: migration-spoke-functional-test

### Migration Spoke Virtual Network
- **Name**: `vnet-nasrehearsal-lab-migration`
- **Address Space**: `10.51.0.0/16`
- **Location**: eastus
- **State**: Succeeded

### Subnets

| Subnet Name | CIDR | IP Range | Size | Purpose | State |
|-------------|------|----------|------|---------|-------|
| snet-migration-vms | 10.51.10.0/24 | 10.51.10.0-255 | 256 IPs | Migration worker VMs | Succeeded |
| snet-rehearsal-nodes | 10.51.20.0/24 | 10.51.20.0-255 | 256 IPs | Virtual PowerScale nodes | Succeeded |
| snet-migration-private-endpoints | 10.51.30.0/24 | 10.51.30.0-255 | 256 IPs | Private endpoints | Succeeded |

### VNet Peering

**Hub → Migration:**
- Name: `peer-hub-to-migration`
- State: Connected
- Allow virtual network access: Yes
- Allow forwarded traffic: Yes
- Allow gateway transit: No

**Migration → Hub:**
- Name: `peer-migration-to-hub`
- State: Connected
- Allow virtual network access: Yes
- Allow forwarded traffic: Yes
- Use remote gateways: No

### Test VM
- **Name**: `vm-nasrehearsal-lab-migration-test`
- **Size**: `Standard_D2als_v7`
- **OS**: Ubuntu 22.04 LTS (Jammy) Gen2
- **Private IP**: 10.51.10.4
- **Public IP**: None (private-only)
- **Authentication**: SSH key (ed25519)
- **Subnet**: snet-migration-vms
- **NSG**: Allows SSH from Hub test subnet (10.50.10.0/24)
- **State**: Succeeded

## Network Layout

```
Migration Spoke VNet: 10.51.0.0/16 (65,536 IPs total)
│
├─ 10.51.10.0/24  snet-migration-vms          (256 IPs)  - Migration worker VMs
├─ 10.51.20.0/24  snet-rehearsal-nodes        (256 IPs)  - Virtual PowerScale nodes
└─ 10.51.30.0/24  snet-migration-private-endpoints (256 IPs)  - Private endpoints (policies disabled)
│
└─ Remaining space available for future use
   └─ 10.51.31.0/24 - 10.51.255.0/24 (225 subnets available)
```

## Directory Structure

```
azure-nas/
└── environments/
    └── rehearsal/
        └── migration-spoke/
            ├── versions.tf          - Terraform and provider version constraints
            ├── providers.tf         - Azure provider with subscription ID
            ├── variables.tf         - Input variable definitions
            ├── main.tf              - Data sources for Hub + Migration RG
            ├── migration-vnet.tf    - Migration VNet and subnets
            ├── peering.tf           - Bidirectional VNet peering
            ├── test-vm.tf           - Test VM with NSG
            ├── outputs.tf           - Output values
            ├── terraform.tfvars     - Variable values (without sensitive values)
            ├── terraform.tfvars.example - Template without sensitive values
            └── tests/
                └── test-peering.sh  - Automated peering and connectivity test
```

## Deployment Commands

### Prerequisites

1. **Generate SSH Key** (if not already existing):
```bash
ssh-keygen -t ed25519 -f ~/.ssh/nas-rehearsal -C "nas-rehearsal"
```

2. **Set SSH public key environment variable**:
```bash
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/nas-rehearsal.pub)"
```

Or use an existing key:
```bash
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
```

3. **Set Azure subscription** (for Azure CLI):
```bash
az account set --subscription "YOUR-SUBSCRIPTION-ID"
az account show --query "{subscription:name,id:id}" --output table
```

4. **Set subscription ID environment variable** (required by migration-spoke/providers.tf):
```bash
export TF_VAR_subscription_id="YOUR-SUBSCRIPTION-ID"
```

**Note**: The Hub configuration does NOT require `TF_VAR_subscription_id` because its providers.tf does not set `subscription_id`. It uses the Azure CLI default. Only the Migration Spoke requires this environment variable.

### Deploy

```bash
cd environments/rehearsal/migration-spoke

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Note: Do NOT add subscription_id to terraform.tfvars
# It is passed via environment variable (see Prerequisites step 4)

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

### Verify Outputs

```bash
terraform output
```

Expected outputs:
- `migration_resource_group_name`
- `migration_vnet_name`
- `migration_vnet_id`
- `migration_subnet_ids` (map of subnet IDs)
- `migration_test_vm_name`
- `migration_test_vm_private_ip`

## Issues Encountered and Resolutions

### Issue 1: VM Size Capacity Restrictions

**Error:**
```
SkuNotAvailable: The requested VM size for resource 'Following SKUs have failed for Capacity Restrictions: Standard_B1s' is currently not available in location 'eastus'.
```

**Cause:**
- `Standard_B1s` has capacity restrictions in eastus region
- Azure cannot provision this VM size due to capacity constraints

**Resolution:**
Changed VM size in `terraform.tfvars`:
- First attempt: `Standard_B1s` → `Standard_B2s` (also unavailable)
- Second attempt: `Standard_B2s` → `Standard_DS1_v2` (also unavailable)
- Final resolution: `Standard_DS1_v2` → `Standard_D2als_v7` (successful)

**Command to check available sizes:**
```bash
az vm list-skus --location eastus --resource-type virtualMachines --all --query "[?name=='Standard_D2als_v7']" --output table
```

### Issue 2: Private Endpoint Subnet Argument Deprecated

**Error:**
Terraform validation error on `private_endpoint_network_policies_enabled = false`

**Cause:**
- AzureRM provider 4.x changed the argument name
- Old: `private_endpoint_network_policies_enabled = false`
- New: `private_endpoint_network_policies = "Disabled"`

**Resolution:**
Updated `migration-vnet.tf`:
```hcl
# Before
private_endpoint_network_policies_enabled = false

# After
private_endpoint_network_policies = "Disabled"
```

### Issue 3: Unsupported Peering State Output

**Error:**
Terraform error: `peering_state` is not a valid attribute for `azurerm_virtual_network_peering`

**Cause:**
- Terraform provider does not export `peering_state` as an attribute
- Attempted to output this value in `outputs.tf`

**Resolution:**
Removed these outputs from `outputs.tf`:
```hcl
# Removed (not supported by Terraform)
output "hub_to_migration_peering_state" {
  value = azurerm_virtual_network_peering.hub_to_migration.peering_state
}

output "migration_to_hub_peering_state" {
  value = azurerm_virtual_network_peering.migration_to_hub.peering_state
}
```

**Alternative verification using Azure CLI:**
```bash
az network vnet peering show \
  --resource-group rg-nasrehearsal-lab-hub \
  --vnet-name vnet-nasrehearsal-lab-hub \
  --name peer-hub-to-migration \
  --query peeringState \
  --output tsv
```

### Issue 4: Hub Test VM Missing for Peering Test

**Error:**
```
ERROR: (ResourceNotFound) The Resource 'Microsoft.Compute/virtualMachines/vm-nasrehearsal-lab-hub-test' under resource group 'rg-nasrehearsal-lab-hub' was not found.
```

**Cause:**
- The peering test script requires a Hub test VM to exist
- Only the Hub VNet and subnets were deployed initially
- No VM was created in the Hub for testing

**Resolution:**
Created Hub test VM configuration:
1. Added `test-vm.tf` to Hub configuration
2. Added `admin_ssh_public_key` variable to Hub `variables.tf`
3. Added `vm_size` variable to Hub `variables.tf`
4. Added `tags` variable to Hub `variables.tf`
5. Updated Hub `main.tf` and `hub-vnet.tf` to use `var.tags`
6. Added VM outputs to Hub `outputs.tf`
7. Deployed Hub test VM with `terraform apply`

**Hub VM details:**
- Name: `vm-nasrehearsal-lab-hub-test`
- Size: `Standard_D2als_v7`
- Private IP: `10.50.10.4`
- NSG: Allows SSH from Migration subnet (10.51.10.0/24)

## Verification Commands

### Check VNet Peering State

**Hub to Migration:**
```bash
az network vnet peering show \
  --resource-group rg-nasrehearsal-lab-hub \
  --vnet-name vnet-nasrehearsal-lab-hub \
  --name peer-hub-to-migration \
  --query peeringState \
  --output tsv
```
**Output:** `Connected`

**Migration to Hub:**
```bash
az network vnet peering show \
  --resource-group rg-nasrehearsal-lab-migration \
  --vnet-name vnet-nasrehearsal-lab-migration \
  --name peer-migration-to-hub \
  --query peeringState \
  --output tsv
```
**Output:** `Connected`

### Verify VM Private IP (No Public IP)

```bash
az vm show \
  --resource-group rg-nasrehearsal-lab-migration \
  --name vm-nasrehearsal-lab-migration-test \
  --show-details \
  --query "{powerState:powerState,privateIps:privateIps,publicIps:publicIps}" \
  --output table
```

**Expected output:**
```
PowerState   PrivateIps    PublicIps
-----------  ------------  ---------
VM running   10.51.10.4
```

### Run Automated Peering Test

```bash
chmod +x tests/test-peering.sh

./tests/test-peering.sh \
  rg-nasrehearsal-lab-hub \
  vm-nasrehearsal-lab-hub-test \
  rg-nasrehearsal-lab-migration \
  vm-nasrehearsal-lab-migration-test
```

**Expected output:**
```
Hub test VM IP:       10.50.10.4
Migration test VM IP: 10.51.10.4
PASS: Hub-to-Migration peering is Connected.
PASS: Migration-to-Hub peering is Connected.
PASS: Migration test VM has no public IP.
Testing Hub VM → Migration VM TCP/22...
PASS
PASS: Hub VM reached Migration VM on TCP/22.
Testing Migration VM → Hub VM TCP/22...
PASS
PASS: Migration VM reached Hub VM on TCP/22.
```

## Test Results

### Peering State
✅ Hub-to-Migration: Connected  
✅ Migration-to-Hub: Connected

### VM Configuration
✅ Hub test VM: 10.50.10.4 (private only)  
✅ Migration test VM: 10.51.10.4 (private only)

### Network Connectivity
✅ Hub VM → Migration VM TCP/22: PASS  
✅ Migration VM → Hub VM TCP/22: PASS

### What This Proves
1. VNet peering is working bidirectionally
2. Private network connectivity between Hub and Spoke
3. NSG rules are correctly configured
4. VMs have no public IP addresses (security best practice)
5. Network routing is functional across peered VNets
6. SSH connectivity works between subnets in different VNets

## Terraform Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `subscription_id` | Azure subscription ID (sensitive) | `YOUR-SUBSCRIPTION-ID` (pass via environment variable) |
| `admin_ssh_public_key` | SSH public key for VM authentication | `YOUR-SSH-PUBLIC-KEY` (pass via environment variable) |

### Optional Variables (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `hub_resource_group_name` | `rg-nasrehearsal-lab-hub` | Hub resource group name |
| `hub_vnet_name` | `vnet-nasrehearsal-lab-hub` | Hub VNet name |
| `hub_test_vm_name` | `vm-nasrehearsal-lab-hub-test` | Hub test VM name |
| `migration_resource_group_name` | `rg-nasrehearsal-lab-migration` | Migration RG name |
| `location` | `eastus` | Azure region |
| `prefix` | `nasrehearsal` | Resource naming prefix |
| `environment` | `lab` | Environment name |
| `admin_username` | `azureadmin` | Linux admin username |
| `vm_size` | `Standard_D2als_v7` | VM size |

## Security Considerations

### Network Security
- **No public IPs** on test VMs (private-only access)
- **NSG rules** restrict SSH to specific subnets
- **VNet peering** enables private communication
- **Private endpoint subnet** has network policies disabled for future private endpoints

### Authentication
- **SSH key authentication** only (password disabled)
- **SSH keys stored locally** (not in Terraform state)
- **Public key passed via environment variable** (not committed to repo)

### Tags
All resources tagged with:
- Project: nas-to-azure
- Environment: lab
- ManagedBy: terraform
- Purpose: migration-spoke-functional-test

## Cost Considerations

### Current Deployed Resources

**Free Resources:**
- Resource Group: Free
- Virtual Network: Free
- Subnets: Free
- VNet Peering: Free

**Billable Resources:**
- Migration Test VM (Standard_D2als_v7): ~$30-50/month depending on usage
- Hub Test VM (Standard_D2als_v7): ~$30-50/month depending on usage
- OS Disk (Standard_LRS): ~$5-10/month

**Estimated Monthly Cost**: ~$70-110/month for both test VMs

### Cost Optimization
- Stop VMs when not in use to reduce compute costs
- Delete entire deployment when testing is complete
- Use smaller VM sizes for non-critical testing

## Cleanup

### Destroy Migration Spoke (first)

```bash
cd environments/rehearsal/migration-spoke
terraform destroy
```

This deletes:
- Migration resource group
- Migration VNet
- Migration subnets
- Migration test VM
- VNet peerings (both directions)

### Destroy Hub (second)

```bash
cd ../hub
terraform destroy
```

This deletes:
- Hub resource group
- Hub VNet
- Hub subnets
- Hub test VM
- All Hub resources

**Important**: Destroy Migration Spoke first, then Hub, to avoid dependency errors.

## Lessons Learned

### 1. VM Size Capacity
- Small VM sizes (B-series) often have capacity restrictions in popular regions
- Use D-series or newer v7 series for better availability
- Always check SKU availability before deployment

### 2. Provider Version Compatibility
- AzureRM provider 4.x has breaking changes from 3.x
- Always check provider documentation for deprecated arguments
- `private_endpoint_network_policies_enabled` → `private_endpoint_network_policies`

### 3. Terraform Output Limitations
- Not all Azure resource attributes are available as Terraform outputs
- Use Azure CLI for verification when Terraform outputs are unavailable
- Peering state must be checked via CLI, not Terraform

### 4. Dependency Management
- Peering requires both VNets to exist
- Connectivity tests require VMs in both VNets
- Deploy in dependency order: Hub first, then Spoke
- Destroy in reverse order: Spoke first, then Hub

### 5. SSH Key Management
- Use environment variables for sensitive values (SSH keys)
- Never commit private keys to version control
- Use `TF_VAR_` prefix for Terraform environment variables

## Next Steps

### Completed
- ✅ Hub VNet with 5 subnets
- ✅ Hub test VM for connectivity testing
- ✅ Migration Spoke VNet with 3 subnets
- ✅ Migration test VM
- ✅ Bidirectional VNet peering
- ✅ Private network connectivity validation

### Future Enhancements
- Deploy Azure Firewall in AzureFirewallSubnet
- Deploy Azure Bastion in AzureBastionSubnet
- Deploy VPN/ExpressRoute Gateway in GatewaySubnet
- Deploy Azure DNS Resolver in snet-dns-resolver
- Create File Services Spoke VNet
- Add Azure Files private endpoints
- Add Azure NetApp Files volumes
- Implement actual migration worker infrastructure

## References

- Main project README: [README.md](../../README.md)
- Hub VNet deployment: [HUB-VNET-DEPLOYMENT.md](../../HUB-VNET-DEPLOYMENT.md)
- Terraform files: `environments/rehearsal/migration-spoke/`
- Test script: `environments/rehearsal/migration-spoke/tests/test-peering.sh`

## Security and Sensitive Data

### Important Security Practices

1. **Never commit sensitive data to version control**:
   - Terraform state files (*.tfstate, *.tfstate.backup)
   - terraform.tfvars files with actual values
   - SSH private keys
   - Subscription IDs
   - API keys or secrets

2. **Use environment variables for sensitive values**:
   ```bash
   export TF_VAR_subscription_id="YOUR-SUBSCRIPTION-ID"
   export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/your-key.pub)"
   ```

3. **Use terraform.tfvars.example as a template**:
   - Copy it to terraform.tfvars
   - Add only non-sensitive values
   - Pass sensitive values via environment variables

4. **.gitignore is configured** to protect:
   - All Terraform state files
   - terraform.tfvars files (except .example)
   - SSH keys
   - Environment files

### What Gets Stored in Terraform State

Terraform state files contain:
- Azure resource IDs (includes subscription ID)
- Resource configurations
- Encrypted secrets (if any)
- Metadata about deployed resources

**Never commit terraform.tfstate files to git.**

### Before Committing to Git

Always run:
```bash
git status
```

Ensure these files are NOT shown:
- terraform.tfstate
- terraform.tfstate.backup
- terraform.tfvars (unless it's .tfvars.example)
- Any .pem, .key, or SSH private key files

## Deployment History

| Date | Action | Status |
|------|--------|--------|
| 2026-10-07 | Initial Migration Spoke deployment attempt | Failed (VM size B1s unavailable) |
| 2026-10-07 | Changed VM size to B2s | Failed (VM size B2s unavailable) |
| 2026-10-07 | Changed VM size to DS1_v2 | Failed (VM size DS1_v2 unavailable) |
| 2026-10-07 | Fixed private endpoint subnet argument | Completed |
| 2026-10-07 | Removed unsupported peering state outputs | Completed |
| 2026-10-07 | Changed VM size to D2als_v7 | Completed |
| 2026-10-07 | Migration Spoke VNet and peering deployed | Completed |
| 2026-10-07 | Migration test VM deployed | Completed |
| 2026-10-07 | Hub test VM added and deployed | Completed |
| 2026-10-07 | Peering connectivity test | All passed |
