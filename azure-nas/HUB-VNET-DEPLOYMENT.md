# Hub VNet Deployment - Current State

This document describes the Hub VNet infrastructure that has been deployed and validated.

## Overview

The Hub VNet is the central networking foundation for the NAS migration architecture. It provides connectivity, security, and DNS resolution services for spoke VNets.

## Deployment Status

✅ **DEPLOYED AND VALIDATED** - October 7, 2026

## What Has Been Built

### Resource Group
- **Name**: `rg-nasrehearsal-lab-hub`
- **Location**: `eastus`
- **State**: Succeeded
- **Tags**:
  - Project: nas-to-azure
  - Environment: lab
  - ManagedBy: terraform

### Hub Virtual Network
- **Name**: `vnet-nasrehearsal-lab-hub`
- **Address Space**: `10.50.0.0/16`
- **Location**: eastus
- **State**: Succeeded

### Subnets

| Subnet Name | CIDR | IP Range | Size | Purpose | State |
|-------------|------|----------|------|---------|-------|
| AzureFirewallSubnet | 10.50.0.0/26 | 10.50.0.0-63 | 64 IPs | Azure Firewall | Succeeded |
| AzureBastionSubnet | 10.50.0.64/26 | 10.50.0.64-127 | 64 IPs | Azure Bastion | Succeeded |
| GatewaySubnet | 10.50.1.0/27 | 10.50.1.0-31 | 32 IPs | VPN/ExpressRoute Gateway | Succeeded |
| snet-dns-resolver | 10.50.2.0/27 | 10.50.2.0-31 | 32 IPs | Azure DNS Resolver | Succeeded |
| snet-hub-test | 10.50.10.0/24 | 10.50.10.0-255 | 256 IPs | Test VMs | Succeeded |

### DNS Resolver Delegation
- **Subnet**: `snet-dns-resolver`
- **Delegation Name**: `dns-resolver-delegation`
- **Service**: `Microsoft.Network/dnsResolvers`
- **Action**: `Microsoft.Network/virtualNetworks/subnets/join/action`
- **State**: Succeeded

## Network Layout

```
Hub VNet: 10.50.0.0/16 (65,536 IPs total)
│
├─ 10.50.0.0/26   AzureFirewallSubnet      (64 IPs)  - Reserved for Azure Firewall
├─ 10.50.0.64/26  AzureBastionSubnet      (64 IPs)  - Reserved for Azure Bastion
├─ 10.50.1.0/27   GatewaySubnet           (32 IPs)  - Reserved for VPN/ExpressRoute Gateway
├─ 10.50.2.0/27   snet-dns-resolver       (32 IPs)  - Azure DNS Resolver with delegation
└─ 10.50.10.0/24  snet-hub-test          (256 IPs)  - For test VMs
│
└─ Remaining space available for future use
   ├─ 10.50.3.0/24 - 10.50.9.0/24   (7 subnets available)
   └─ 10.50.11.0/24 - 10.50.255.0/24 (245 subnets available)
```

## Directory Structure

```
azure-nas/
└── environments/
    └── rehearsal/
        └── hub/
            ├── versions.tf          - Terraform and provider version constraints
            ├── providers.tf         - Azure provider configuration
            ├── variables.tf         - Input variable definitions
            ├── main.tf              - Resource group
            ├── hub-vnet.tf           - VNet and subnet resources
            ├── outputs.tf           - Output values
            ├── terraform.tfvars     - Variable values
            └── tests/
                └── test-hub.sh      - Automated validation script
```

## Deployment Commands

### Prerequisites
```bash
az login
az account set --subscription "<your-subscription-id>"
az account show --query "{subscription:name,id:id}" --output table
```

### Deploy
```bash
cd environments/rehearsal/hub
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

**Terraform fmt output**:
```
outputs.tf
```
**Result**: Formatted `outputs.tf` to align subnet_ids map spacing for consistency

## Verification Commands Used

The following commands were used to verify the deployment:

### Check Subscription
```bash
az account list --output table
```
**Output**:
```
Name                  CloudName    SubscriptionId                        TenantId                              State    IsDefault
--------------------  -----------  ------------------------------------  ------------------------------------  -------  -----------
Azure subscription 1  AzureCloud   YOUR-SUBSCRIPTION-ID  YOUR-TENANT-ID  Enabled  True
```
**Result**: Confirmed subscription is active and set as default

### Verify Active Subscription
```bash
az account show --query "{subscription:name,id:id}" --output table
```
**Output**:
```
Subscription
--------------------
Azure subscription 1
```

### Verify Resource Group
```bash
az group show \
  --name rg-nasrehearsal-lab-hub \
  --query "{name:name,location:location,state:properties.provisioningState}" \
  --output table
```
**Output**:
```
Name                     Location    State
-----------------------  ----------  ---------
rg-nasrehearsal-lab-hub  eastus      Succeeded
```

### Verify VNet
```bash
az network vnet show \
  --resource-group rg-nasrehearsal-lab-hub \
  --name vnet-nasrehearsal-lab-hub \
  --output json
```
**Output**: Confirmed VNet with address space `10.50.0.0/16` and all 5 subnets

### Verify All Subnets
```bash
az network vnet subnet list \
  --resource-group rg-nasrehearsal-lab-hub \
  --vnet-name vnet-nasrehearsal-lab-hub \
  --query "[].{name:name,cidr:addressPrefix,state:provisioningState}" \
  --output table
```
**Output**: All 5 subnets listed with correct CIDRs and Succeeded state

### Verify DNS Resolver Delegation
```bash
az network vnet subnet show \
  --resource-group rg-nasrehearsal-lab-hub \
  --vnet-name vnet-nasrehearsal-lab-hub \
  --name snet-dns-resolver \
  --output json
```
**Output**: Confirmed delegation to `Microsoft.Network/dnsResolvers` with action `Microsoft.Network/virtualNetworks/subnets/join/action`

### Run Automated Tests
```bash
chmod +x tests/test-hub.sh
./tests/test-hub.sh rg-nasrehearsal-lab-hub vnet-nasrehearsal-lab-hub
```
**Output**:
```
Checking hub VNet address space...
PASS: Hub VNet CIDR is 10.50.0.0/16
PASS: AzureFirewallSubnet is 10.50.0.0/26
PASS: AzureBastionSubnet is 10.50.0.64/26
PASS: GatewaySubnet is 10.50.1.0/27
PASS: snet-dns-resolver is 10.50.2.0/27
PASS: snet-hub-test is 10.50.10.0/24
PASS: Hub network structure matches the expected design.
```

## Terraform Outputs

After deployment, Terraform outputs the following values:

```bash
terraform output
```

- `resource_group_name` - Name of the resource group
- `resource_group_location` - Location of the resource group
- `vnet_name` - Name of the hub virtual network
- `vnet_id` - Azure resource ID of the hub virtual network
- `vnet_address_space` - Address space of the hub virtual network
- `subnet_ids` - Map of subnet IDs keyed by subnet name

## What Has NOT Been Deployed Yet

The following resources are planned but not yet deployed:

### Hub Services
- Azure Firewall (requires AzureFirewallSubnet)
- Azure Bastion (requires AzureBastionSubnet)
- VPN Gateway or ExpressRoute Gateway (requires GatewaySubnet)
- Azure DNS Resolver resources (requires snet-dns-resolver with delegation)
- Test VM in snet-hub-test

### Spoke VNets
- Migration Spoke VNet (10.51.0.0/16)
- File Services Spoke VNet (10.52.0.0/16)
- VNet peerings between Hub and Spokes

### Storage
- Azure Files private endpoints
- Azure NetApp Files volumes
- Private DNS zones

## Next Steps

### Option 1: Add Test VM (Step 4)
Deploy a small Linux VM in `snet-hub-test` to validate:
- VM boots successfully
- Private NIC receives IP address
- Routes are correctly configured
- Azure Run Command works for remote access

### Option 2: Deploy Hub Services
Add Azure Firewall, Bastion, or Gateway resources to enable:
- Network inspection and filtering
- Secure remote access
- Site-to-site or point-to-site connectivity

### Option 3: Create Migration Spoke
Build the Migration Spoke VNet with:
- Test VMs
- Migration worker infrastructure
- VNet peering to Hub

### Option 4: Deploy DNS Resolver
Add actual Azure DNS Resolver resources:
- DNS Resolver instance
- Inbound endpoint
- Outbound endpoint
- Private DNS zone integration

## Validation Checklist

- [x] Resource group created in correct region
- [x] Hub VNet created with correct address space (10.50.0.0/16)
- [x] AzureFirewallSubnet created (10.50.0.0/26)
- [x] AzureBastionSubnet created (10.50.0.64/26)
- [x] GatewaySubnet created (10.50.1.0/27)
- [x] snet-dns-resolver created (10.50.2.0/27) with delegation
- [x] snet-hub-test created (10.50.10.0/24)
- [x] All subnets non-overlapping
- [x] DNS Resolver delegation configured correctly
- [x] Tags applied to all resources
- [x] Automated test script passes all checks
- [ ] Test VM deployed and functional
- [ ] VNet peering to Migration Spoke
- [ ] Connectivity testing between VNets

## Cost Considerations

Current deployed resources incur minimal costs:
- Resource Group: Free
- Virtual Network: Free
- Subnets: Free

Future resources will incur costs:
- Azure Firewall: ~$1.25/hour + data processing
- Azure Bastion: ~$0.20/hour
- VPN Gateway: ~$0.30/hour
- DNS Resolver: ~$0.20/hour per endpoint
- Test VMs: Depends on size and usage

## Cleanup

To remove all deployed resources:

```bash
cd environments/rehearsal/hub
terraform destroy
```

Type `yes` when prompted. This will delete:
- Resource group
- Virtual network
- All subnets
- Any resources created within them

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
   export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/your-key.pub)"
   ```

3. **.gitignore is configured** to protect:
   - All Terraform state files
   - terraform.tfvars files
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
- terraform.tfvars
- Any .pem, .key, or SSH private key files

## References

- Main project README: [README.md](./README.md)
- Terraform files: `environments/rehearsal/hub/`
- Test script: `environments/rehearsal/hub/tests/test-hub.sh`

## Deployment History

| Date | Action | Status |
|------|--------|--------|
| 2026-10-07 | Initial Hub VNet deployment | Completed |
| 2026-10-07 | Automated validation tests | All passed |
