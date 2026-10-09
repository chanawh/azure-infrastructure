# Virtual PowerScale to Azure NAS Migration Foundation

This repository builds the Azure foundation and migration operations needed to rehearse and migrate an on-premises PowerScale/OneFS NAS estate.

The design supports:

- **Azure Files Premium** for SMB workloads.
- **Azure NetApp Files** for NFS-heavy Linux workloads.
- Private connectivity through VPN or ExpressRoute.
- Active Directory Domain Services authentication for SMB.
- Private endpoints, Private DNS, Azure Firewall, and Azure Bastion.
- Terraform-managed Azure infrastructure.
- Python tooling for inventory, delta-copy orchestration, checksum manifests, and cutover checks.
- A virtual PowerScale cluster used as a **non-production rehearsal source**.

> **Important:** Confirm Dell’s current PowerScale Virtual Edition support matrix, licensing terms, supported hypervisors, and Azure IaaS guidance before deployment.  
> This repository creates the Azure network and supporting compute foundation. It does not replace Dell deployment artifacts or claim that every virtual OneFS configuration is supported in Azure.

---

## Table of Contents

- [Business Problem](#business-problem)
- [Project Goals](#project-goals)
- [Architecture](#architecture)
- [Virtual PowerScale Rehearsal Scope](#virtual-powerscale-rehearsal-scope)
- [Network Design](#network-design)
- [Identity and Access Design](#identity-and-access-design)
- [Storage Design](#storage-design)
- [Migration Method](#migration-method)
- [Integrity Verification](#integrity-verification)
- [Backup and Recovery](#backup-and-recovery)
- [Security Controls](#security-controls)
- [Cost Guardrails](#cost-guardrails)
- [Repository Layout](#repository-layout)
- [Terraform Deployment](#terraform-deployment)
- [Python Migration Tooling](#python-migration-tooling)
- [Cutover Runbook](#cutover-runbook)
- [Rollback Runbook](#rollback-runbook)
- [Validation and Testing](#validation-and-testing)
- [Definition of Done](#definition-of-done)

---

# Business Problem

The enterprise runs an on-premises PowerScale/OneFS NAS platform that serves Windows and Linux workloads.

| Area | Current State |
|---|---|
| Source platform | Dell PowerScale / OneFS |
| Total data | 80 TB |
| Shares | 6 file shares |
| Users | 400+ |
| Protocols | SMB and NFS |
| Authentication | Active Directory-integrated |
| Current DR | Nightly `rsync` to a second on-premises array |
| Current RPO | 24 hours |
| Current RTO | Untested |
| Hardware status | Approaching end of support |
| Cloud presence | None |

The business plans to exit the datacenter within 12 months.

---

# Project Goals

## Target State

| Requirement | Target |
|---|---|
| SMB destination | Azure Files Premium |
| NFS destination | Azure NetApp Files |
| Connectivity | Private VPN or ExpressRoute |
| Public storage access | Disabled |
| SMB identity | Active Directory Domain Services |
| Migration model | Initial seed, incremental deltas, final cutover |
| Integrity proof | File count, metadata, and SHA-256 checksum manifests |
| Backup retention | At least 30 days |
| Backup immutability | Enabled where supported and approved |
| Target RPO | 4 hours |
| Target RTO | Under 8 hours |
| Infrastructure | Terraform |
| Migration operations | Python tooling and runbooks |
| Monthly Azure budget | Under `$8,000` |
| Budget warning | `$6,000` or 75% |
| Rollback period | 30 days after cutover |

## Success Criteria

The migration is successful only when:

- [ ] Every source file exists in the target location.
- [ ] Source and destination checksum manifests match.
- [ ] SMB ACL behavior is validated for representative AD users.
- [ ] NFS UID and GID ownership is validated for Linux workloads.
- [ ] Each share cutover completes inside its six-hour weekend window.
- [ ] No unplanned outage occurs during migration activity.
- [ ] On-premises shares remain available for rollback for 30 days.
- [ ] Quarterly restore tests demonstrate an RTO below eight hours.
- [ ] Terraform can rebuild the Azure foundation from a clean environment.
- [ ] Any trained engineer can execute the documented cutover runbook.

> A final write freeze is expected during cutover. The goal is zero **unplanned** downtime, not unrestricted writes during a consistency checkpoint.

---

# Architecture

## High-Level Design

```text
                                  ON-PREMISES DATACENTER
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ┌──────────────────────┐         ┌────────────────────────┐                │
│  │ Production PowerScale │         │ Active Directory Domain │                │
│  │ / OneFS Cluster       │         │ Controllers and DNS     │                │
│  │                      │         │                        │                │
│  │ SMB and NFS shares   │         │ Users, groups, SIDs     │                │
│  └──────────┬───────────┘         └────────────┬───────────┘                │
│             │                                  │                             │
└─────────────┼──────────────────────────────────┼─────────────────────────────┘
              │                                  │
              │ VPN or ExpressRoute              │ AD DNS and authentication
              ▼                                  ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                                  AZURE                                         │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │ Hub VNet: 10.50.0.0/16                                                  │ │
│  │                                                                         │ │
│  │ GatewaySubnet        AzureFirewallSubnet        AzureBastionSubnet      │ │
│  │      │                       │                        │                 │ │
│  │ VPN / ExpressRoute      Azure Firewall         Azure Bastion             │ │
│  │      │                       │                        │                 │ │
│  │      └──── Private DNS, routes, inspection, and administration ────────┤ │
│  └────────────────────────────┬───────────────────────────┬────────────────┘ │
│                               │                           │                  │
│                         VNet Peering                 VNet Peering             │
│                               │                           │                  │
│  ┌────────────────────────────▼───────┐  ┌────────────────▼───────────────┐ │
│  │ Migration Spoke: 10.51.0.0/16      │  │ File Services Spoke:           │ │
│  │                                    │  │ 10.52.0.0/16                   │ │
│  │ - Migration worker VMs             │  │                                │ │
│  │ - Python copy tooling              │  │ - Azure Files private endpoint │ │
│  │ - Manifest verification            │  │ - Azure NetApp Files subnet    │ │
│  │ - Virtual PowerScale rehearsal     │  │ - Application private access   │ │
│  │   nodes, if vendor-supported       │  │                                │ │
│  └────────────────────────────────────┘  └────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Required Data Paths

```text
Production PowerScale / OneFS
  → VPN or ExpressRoute
  → Migration worker VM
  → Azure Firewall, when required by routing policy
  → Azure Files private endpoint or Azure NetApp Files mount target

Migration worker VM
  → Private DNS zone
  → Private IP address for Azure Files

Administrator browser
  → Azure Bastion
  → Migration worker or approved management VM

Windows client
  → Private network
  → Azure Files SMB endpoint

Linux client
  → Private network
  → Azure NetApp Files NFS mount target
```

No migration worker, rehearsal node, Azure Files endpoint, or Azure NetApp Files resource receives a public IP address.

---

# Virtual PowerScale Rehearsal Scope

A virtual PowerScale cluster is used to test migration behavior before production cutovers.

The virtual cluster is **not** the authoritative source for the 80 TB production dataset. Production migration data continues to come from the on-premises PowerScale cluster.

## Rehearsal Goals

The rehearsal environment should prove:

- Private network connectivity between source, migration workers, and Azure targets.
- SMB access using Active Directory users and groups.
- SMB ACL behavior and inheritance.
- NFS export behavior.
- UID and GID mapping for Linux workloads.
- Initial seed workflow.
- Four-hour incremental delta workflow.
- Checksum manifest generation and comparison.
- Cutover timing and validation steps.
- Rollback procedures.

## Representative Rehearsal Dataset

Create test data that includes:

- Large files greater than 10 GB.
- Many small files.
- Deep directory structures.
- Files with long names.
- Files with special characters.
- Windows ACL inheritance examples.
- Explicit deny ACL examples.
- Linux files owned by service accounts.
- Multiple UID and GID combinations.
- Files changed frequently during delta-copy testing.

## Virtual Cluster Guardrails

- Do not place PHI or PII in rehearsal data.
- Do not assign public IP addresses to rehearsal nodes.
- Do not use rehearsal nodes as production disaster recovery storage.
- Do not treat a successful rehearsal as proof that production data needs no validation.
- Document Dell support and licensing status before deployment.

---

# Network Design

## VNet Address Plan

| VNet | CIDR | Role |
|---|---:|---|
| Hub VNet | `10.50.0.0/16` | Connectivity, security inspection, administration, and DNS |
| Migration Spoke | `10.51.0.0/16` | Migration workers and rehearsal infrastructure |
| File Services Spoke | `10.52.0.0/16` | Azure Files private endpoints and Azure NetApp Files |

## Subnet Plan

| VNet | Subnet | CIDR | Role |
|---|---|---:|---|
| Hub | `AzureFirewallSubnet` | `10.50.0.0/26` | Azure Firewall only |
| Hub | `AzureBastionSubnet` | `10.50.0.64/26` | Azure Bastion only |
| Hub | `GatewaySubnet` | `10.50.1.0/27` | VPN Gateway or ExpressRoute Gateway |
| Hub | `snet-dns-resolver` | `10.50.2.0/27` | Optional Azure DNS Private Resolver |
| Migration | `snet-migration-vms` | `10.51.10.0/24` | Sync workers, manifest tools, orchestration |
| Migration | `snet-rehearsal-nodes` | `10.51.20.0/24` | Supported virtual PowerScale nodes |
| Migration | `snet-migration-private-endpoints` | `10.51.30.0/24` | Private endpoints used by migration services |
| File Services | `snet-file-private-endpoints` | `10.52.10.0/24` | Azure Files private endpoints |
| File Services | `snet-anf-delegated` | `10.52.20.0/24` | Azure NetApp Files delegated subnet |

Each subnet has one job. Do not mix Firewall, Bastion, gateways, private endpoints, migration VMs, or rehearsal nodes.

## Network Rules

- Peer each workload spoke with the hub.
- Do not peer spokes directly unless a tested workload requires it.
- Enable forwarded traffic on relevant hub-and-spoke peerings.
- Use route tables to send inspected traffic through Azure Firewall.
- Keep private-endpoint DNS zones linked to every VNet that needs name resolution.
- Use a DNS forwarder or Azure DNS Private Resolver for on-premises private DNS resolution.
- Restrict management access to Azure Bastion and approved administrative identities.

---

# Identity and Access Design

## Active Directory Dependencies

Azure Files SMB authentication requires Active Directory Domain Services.

Before deploying Azure Files for production use, confirm:

1. Azure networks can resolve AD DNS records.
2. Azure networks can reach domain controllers.
3. Time synchronization is correct for Kerberos.
4. The storage account has the required AD DS identity configuration.
5. AD permissions have been delegated correctly.
6. Azure RBAC share permissions are assigned.
7. Existing NTFS ACLs are migrated and tested.

## SMB Validation

Test each share with representative users:

- Standard read-only user.
- Standard modify user.
- Share owner.
- User explicitly denied access.
- Service account.
- Nested AD group member.

Validate:

- SMB mount success.
- Read access.
- Create, edit, rename, and delete operations.
- ACL inheritance.
- Explicit deny behavior.
- Kerberos authentication.
- SMB encryption requirements.

## NFS Validation

For Azure NetApp Files, validate:

- Required NFS version.
- Mount options.
- UID mapping.
- GID mapping.
- Service account ownership.
- Root access behavior.
- Application read and write behavior.
- Performance under representative workload conditions.

---

# Storage Design

## SMB Workloads: Azure Files Premium

Use Azure Files Premium for SMB workloads that fit Azure Files features and performance requirements.

Required controls:

- Premium `FileStorage` account tier.
- Public network access disabled.
- Azure Files private endpoint.
- Private DNS zone: `privatelink.file.core.windows.net`.
- AD DS authentication configured.
- Share-level RBAC assigned.
- Backup policy applied.
- Diagnostic settings enabled.

## NFS Workloads: Azure NetApp Files

Use Azure NetApp Files for NFS-heavy workloads that need managed NFS performance and semantics.

Required controls:

- Delegated ANF subnet.
- Capacity pool sized from measured demand.
- Volume quotas set per workload.
- Snapshot and backup policy documented.
- Private access only.
- NFS client access limited to approved network ranges.

> Azure NetApp Files capacity pools can drive a large part of monthly cost. Size them from measured workload demand before production approval.

---

# Private DNS Design

Create and link Private DNS zones as required.

| Private DNS Zone | Purpose |
|---|---|
| `privatelink.file.core.windows.net` | Azure Files private endpoints |
| `privatelink.blob.core.windows.net` | Blob storage for manifests and reports |
| `privatelink.vaultcore.azure.net` | Azure Key Vault private endpoint |
| `privatelink.monitor.azure.com` | Azure Monitor private access, if used |
| `privatelink.oms.opinsights.azure.com` | Log Analytics private access, if used |

Validate that a migration worker resolves Azure Files names to private RFC1918 addresses.

Example:

```bash
nslookup <storage-account-name>.file.core.windows.net
```

The result should resolve through the private endpoint path, not a public Azure address.

---

# Migration Method

## Phase 1: Discovery

For each share, capture:

- Share name.
- Protocol: SMB, NFS, or mixed.
- Total bytes.
- File count.
- Directory count.
- Largest file.
- Daily change rate.
- Business owner.
- Application dependencies.
- ACL complexity.
- UID/GID requirements.
- Planned Azure destination.
- Cutover weekend.
- Rollback owner.

Store the inventory in `docs/share-inventory.csv`.

## Phase 2: Rehearsal

Use the virtual PowerScale test source to rehearse:

1. Initial seed.
2. Incremental delta copy.
3. Checksum generation.
4. Manifest comparison.
5. Azure Files SMB access.
6. Azure NetApp Files NFS access.
7. Cutover timing.
8. Rollback.

## Phase 3: Initial Seed

Perform the baseline copy from on-premises PowerScale to Azure.

The 80 TB seed duration depends on usable bandwidth.

```text
Transfer time = data size in bits / usable throughput in bits per second
```

Example:

```text
80 TB is about 640 terabits.

At 1 Gbps sustained:
640,000 seconds
About 7.4 days.

At 200 Mbps sustained:
3,200,000 seconds
About 37 days.
```

Actual transfer time increases because of small-file overhead, metadata operations, encryption, retries, concurrent source changes, and protocol overhead.

If WAN throughput cannot support the migration plan, evaluate an approved offline seed method before committing cutover dates.

## Phase 4: Incremental Delta Copies

Run deltas at least every four hours.

Each delta run must record:

- Start and end time.
- Source share.
- Destination share.
- Files scanned.
- Files copied.
- Files changed.
- Files deleted, if deletion sync is approved.
- Bytes transferred.
- Errors.
- Retry count.
- Manifest location.

Alert when a delta run exceeds four hours or overlaps the next scheduled run.

## Phase 5: Final Verification

Before cutover:

1. Stop or freeze writes.
2. Run the final delta.
3. Generate final manifests.
4. Compare manifests.
5. Resolve every mismatch or approve documented exceptions.
6. Validate access paths.
7. Switch client access.

---

# Integrity Verification

A successful copy command does not prove every file migrated correctly.

## Manifest Format

Each JSON Lines record should include:

```json
{
  "share_name": "finance",
  "relative_path": "reports/2026/q1.xlsx",
  "file_type": "file",
  "size_bytes": 1048576,
  "modified_time_utc": "2026-10-07T12:00:00Z",
  "uid": 10001,
  "gid": 10001,
  "mode": "0640",
  "acl_hash": "sha256-of-normalized-acl",
  "sha256": "file-content-sha256",
  "scan_time_utc": "2026-10-07T12:30:00Z"
}
```

## Pass Conditions

A share passes integrity verification when:

- Source and destination file counts match.
- Source and destination directory counts match.
- Aggregate byte counts match.
- Every required file has a matching SHA-256 hash.
- NFS ownership and mode values match approved expectations.
- SMB ACL checks pass for approved test identities.
- Any exceptions are documented, approved, and retained with cutover evidence.

---

# Backup and Recovery

## Backup Requirements

| Requirement | Target |
|---|---|
| Retention | At least 30 days |
| Restore test frequency | Quarterly |
| Target RPO | 4 hours |
| Target RTO | Under 8 hours |
| Evidence | Ticket, logs, timing, and business validation |

## Backup Scope

| Asset | Backup or Protection Method |
|---|---|
| Azure Files | Azure Backup for Azure Files |
| Azure NetApp Files | ANF snapshots, ANF backup, and approved recovery plan |
| Terraform state | Versioned Azure Storage blob |
| Manifests and reports | Versioned or immutable Blob storage |
| Migration scripts | Git repository and release tags |
| Key Vault | Soft delete, purge protection, and recovery process |

## Restore Test Evidence

Every quarterly test should record:

- Dataset size.
- Restore method.
- Start time.
- End time.
- Total duration.
- Validation result.
- Business owner sign-off.
- Any follow-up actions.

---

# Security Controls

## Required Controls

- Disable public access for Azure Storage accounts.
- Use private endpoints for Azure Files, Key Vault, and other approved PaaS services.
- Use Azure Bastion for VM administration.
- Do not assign public IPs to migration workers or rehearsal nodes.
- Send inspected traffic through Azure Firewall where routing policy requires it.
- Store secrets in Azure Key Vault.
- Use managed identities where supported.
- Enforce TLS 1.2 or newer.
- Encrypt data at rest.
- Keep data and diagnostics inside the approved Azure region.
- Apply least-privilege Azure RBAC.
- Enable diagnostics for network, storage, and backup services.
- Apply resource locks to production backup resources after validation.

## Data Classification

Use consistent tags:

```hcl
tags = {
  Project     = "nas-to-azure"
  Environment = "rehearsal"
  ManagedBy   = "terraform"
  CostCenter  = "cloud-migration"
  DataClass   = "restricted"
  Owner       = "storage-platform"
}
```

---

# Cost Guardrails

The target monthly Azure spend must remain below `$8,000`.

| Threshold | Amount | Action |
|---|---:|---|
| Budget | `$8,000` | Monthly hard target |
| Warning | `$6,000` | Notify cloud operations and project owner |
| Critical | `$7,200` | Require review before new capacity changes |

Monitor costs for:

- Azure NetApp Files capacity pools.
- Azure Files Premium provisioned capacity.
- VPN Gateway or ExpressRoute.
- Azure Firewall.
- Azure Bastion.
- Backup storage.
- Log Analytics ingestion.
- Migration VM compute and disks.
- Data egress, if any workload requires it.

---

# Repository Layout

```text
azure-nas/
├── README.md
├── .gitignore
├── HUB-VNET-DEPLOYMENT.md           # Hub VNet deployment documentation
├── MIGRATION-SPOKE-DEPLOYMENT.md    # Migration Spoke deployment documentation
└── environments/
    └── rehearsal/
        ├── hub/
        │   ├── versions.tf
        │   ├── providers.tf
        │   ├── variables.tf
        │   ├── main.tf
        │   ├── hub-vnet.tf
        │   ├── test-vm.tf
        │   ├── outputs.tf
        │   ├── terraform.tfvars
        │   └── tests/
        │       └── test-hub.sh
        └── migration-spoke/
            ├── versions.tf
            ├── providers.tf
            ├── variables.tf
            ├── main.tf
            ├── migration-vnet.tf
            ├── peering.tf
            ├── test-vm.tf
            ├── outputs.tf
            ├── terraform.tfvars
            ├── terraform.tfvars.example
            └── tests/
                └── test-peering.sh
```

---

# Security and Sensitive Data

## Important Security Practices

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

## What Gets Stored in Terraform State

Terraform state files contain:
- Azure resource IDs (includes subscription ID)
- Resource configurations
- Encrypted secrets (if any)
- Metadata about deployed resources

**Never commit terraform.tfstate files to git.**

## Before Committing to Git

Always run:
```bash
git status
```

Ensure these files are NOT shown:
- terraform.tfstate
- terraform.tfstate.backup
- terraform.tfvars (unless it's .tfvars.example)
- Any .pem, .key, or SSH private key files

---

# Terraform Deployment
│   ├── pre-cutover-checklist.md
│   ├── cutover.md
│   ├── rollback.md
│   └── restore-test.md
└── docs/
    ├── architecture.md
    ├── share-inventory-template.csv
    ├── firewall-rule-matrix.md
    └── test-evidence-template.md
```

---

# Terraform Deployment

## Prerequisites

Install these tools before deploying:

- Terraform `1.6.0` or newer
- Azure CLI
- Git
- An Azure subscription
- Permission to create resource groups, VNets, and VMs

## Authentication

Sign in to Azure CLI:
```bash
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
az account show --query "{subscription:name,id:id}" --output table
```

**Note**: The Hub configuration uses the Azure CLI default subscription. The Migration Spoke requires setting `TF_VAR_subscription_id` as shown below.

## Deployment Order

### 1. Deploy Hub VNet

```bash
cd environments/rehearsal/hub

# Set SSH public key environment variable
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/your-key.pub)"

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

See [HUB-VNET-DEPLOYMENT.md](./HUB-VNET-DEPLOYMENT.md) for detailed documentation.

### 2. Deploy Migration Spoke

```bash
cd environments/rehearsal/migration-spoke

# Set subscription ID environment variable (REQUIRED by migration-spoke/providers.tf)
export TF_VAR_subscription_id="YOUR-SUBSCRIPTION-ID"

# Set SSH public key environment variable
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/your-key.pub)"

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

**Important**: The Migration Spoke requires `TF_VAR_subscription_id` because its `providers.tf` explicitly sets `subscription_id = var.subscription_id`. The Hub does not require this and uses the Azure CLI default.

See [MIGRATION-SPOKE-DEPLOYMENT.md](./MIGRATION-SPOKE-DEPLOYMENT.md) for detailed documentation.

## Terraform Commands

```bash
terraform init          # Initialize working directory and download providers
terraform fmt -recursive  # Format all Terraform files
terraform validate       # Validate syntax and configuration
terraform plan           # Preview changes
terraform apply          # Apply changes
terraform destroy        # Destroy resources
```

---

# Current Deployment Status

## Deployed Infrastructure

✅ **Hub VNet** - Complete with 5 subnets and test VM
- Resource Group: rg-nasrehearsal-lab-hub
- VNet: vnet-nasrehearsal-lab-hub (10.50.0.0/16)
- Subnets: AzureFirewallSubnet, AzureBastionSubnet, GatewaySubnet, snet-dns-resolver, snet-hub-test
- Test VM: vm-nasrehearsal-lab-hub-test (10.50.10.4)

✅ **Migration Spoke** - Complete with VNet peering and test VM
- Resource Group: rg-nasrehearsal-lab-migration
- VNet: vnet-nasrehearsal-lab-migration (10.51.0.0/16)
- Subnets: snet-migration-vms, snet-rehearsal-nodes, snet-migration-private-endpoints
- Test VM: vm-nasrehearsal-lab-migration-test (10.51.10.4)
- VNet Peering: Bidirectional, Connected

✅ **Network Connectivity** - Validated
- Hub ↔ Migration peering: Connected
- TCP/22 connectivity between VMs: Working

## Documentation

- [HUB-VNET-DEPLOYMENT.md](./HUB-VNET-DEPLOYMENT.md) - Complete Hub VNet deployment documentation
- [MIGRATION-SPOKE-DEPLOYMENT.md](./MIGRATION-SPOKE-DEPLOYMENT.md) - Complete Migration Spoke deployment documentation

---

# Remote State (Future)

Use Azure Storage for shared Terraform state.

Required state controls:

- Blob versioning.
- Restricted Azure RBAC.
- Separate state keys per environment.
- No state files committed to Git.
- Private endpoint access if your network policy requires it.

Example:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stnasterraformstate"
    container_name       = "tfstate"
    key                  = "rehearsal.terraform.tfstate"
  }
}
```

---

# Python Migration Tooling

## Required Scripts

| Script | Purpose |
|---|---|
| `inventory.py` | Collect source paths, sizes, counts, and metadata |
| `seed.py` | Start or record the baseline copy process |
| `delta_sync.py` | Run and record incremental copy jobs |
| `checksum_manifest.py` | Create SHA-256 manifests |
| `verify_manifest.py` | Compare source and destination manifests |
| `cutover_check.py` | Verify cutover prerequisites |

## Example Commands

```bash
python scripts/inventory.py \
  --share finance \
  --source /mnt/source/finance \
  --output docs/inventory/finance.json

python scripts/checksum_manifest.py \
  --root /mnt/source/finance \
  --output manifests/finance-source.jsonl

python scripts/checksum_manifest.py \
  --root /mnt/destination/finance \
  --output manifests/finance-destination.jsonl

python scripts/verify_manifest.py \
  --source manifests/finance-source.jsonl \
  --destination manifests/finance-destination.jsonl

python scripts/cutover_check.py \
  --share finance \
  --max-window-hours 6
```

Do not store passwords, storage keys, or long-lived tokens in scripts or Terraform files.

Use managed identities, Key Vault, and short-lived Azure authentication where possible.

---

# Cutover Runbook

Each share receives an individual weekend cutover.

## Pre-Cutover Checklist

- [ ] Business owner approves the change window.
- [ ] Application owner is available.
- [ ] Latest delta completed successfully.
- [ ] Delta duration is below four hours.
- [ ] Final manifest process is tested.
- [ ] Azure Files or ANF destination is reachable privately.
- [ ] AD authentication tests passed.
- [ ] Backup policy is applied.
- [ ] Restore test evidence exists.
- [ ] Rollback owner is assigned.
- [ ] On-premises source remains available.
- [ ] Six-hour cutover timer is started.

## Cutover Steps

```text
1. Announce maintenance start.
2. Stop application writes to the source share.
3. Make the source share read-only where practical.
4. Run the final incremental sync.
5. Generate source and destination manifests.
6. Compare manifests.
7. Resolve failures or invoke rollback.
8. Switch DFS namespace, UNC path, mount target, or application configuration.
9. Test access with representative users and applications.
10. Monitor authentication, errors, throughput, and latency.
11. Obtain business-owner acceptance.
12. Record completion evidence.
```

## Cutover Pass Conditions

- Final delta completed.
- Manifest verification passed.
- Required users can access data.
- Required applications pass smoke tests.
- SMB ACL behavior is correct.
- NFS ownership and access is correct.
- No major monitoring alerts exist.
- Work completed inside the six-hour window.

---

# Rollback Runbook

Rollback remains available for 30 days after cutover.

## Rollback Triggers

- Unresolved checksum mismatch.
- Application failure.
- Authentication or ACL failure.
- Incorrect NFS UID/GID behavior.
- Performance below agreed target.
- Data-access failure.
- Cutover cannot complete inside the approved window.

## Rollback Steps

```text
1. Stop writes to the Azure destination.
2. Re-enable writes to the on-premises PowerScale source.
3. Revert DFS namespace, UNC path, mount target, or application configuration.
4. Validate on-premises user and application access.
5. Preserve Azure logs, manifests, and error output.
6. Document the rollback reason.
7. Create corrective actions before rescheduling cutover.
```

Do not delete or repurpose the on-premises source share during the 30-day rollback period.

---

# Validation and Testing

## Network Tests

- [ ] On-premises systems can reach approved Azure private addresses.
- [ ] Azure migration workers can resolve AD DNS records.
- [ ] Azure Files resolves to private endpoint addresses.
- [ ] Migration workers have no public IP addresses.
- [ ] Azure Bastion provides approved administrative access.
- [ ] Firewall logs show expected inspected traffic.
- [ ] Unauthorized network paths are blocked.

## Identity Tests

- [ ] Domain user can mount SMB share.
- [ ] Unauthorized user is denied.
- [ ] NTFS inheritance behaves correctly.
- [ ] Azure Files share-level permissions work.
- [ ] Linux users preserve expected UID and GID behavior.
- [ ] NFS service accounts can access required paths.

## Migration Tests

- [ ] Initial seed completes.
- [ ] Delta copy completes in four hours or less.
- [ ] Source and destination file counts match.
- [ ] Source and destination checksums match.
- [ ] Cutover rehearsal completes in six hours or less.
- [ ] Rollback rehearsal succeeds.

## Recovery Tests

- [ ] Azure Files restore test completes in under eight hours.
- [ ] ANF recovery test completes in under eight hours.
- [ ] Test results are documented.
- [ ] Corrective actions are tracked.

---

# Definition of Done

The project is complete when:

- [ ] Terraform deploys the private Azure foundation.
- [ ] Hub-and-spoke network paths are tested.
- [ ] Azure Files and ANF have no public data access.
- [ ] Virtual PowerScale rehearsal is documented and vendor support is confirmed.
- [ ] SMB identity and ACL behavior are validated.
- [ ] NFS UID/GID behavior is validated.
- [ ] Four-hour delta synchronization is proven.
- [ ] Every migrated share has matching checksum evidence.
- [ ] Every share cutover completes inside six hours.
- [ ] Rollback is tested and possible for 30 days.
- [ ] Backup retention is at least 30 days.
- [ ] Quarterly restore tests meet the eight-hour RTO.
- [ ] Budget alerts trigger at `$6,000` and `$7,200`.
- [ ] Another engineer can run the documented process without undocumented knowledge.