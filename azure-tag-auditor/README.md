# Azure Untagged Resource Auditor

A Python project that audits Azure resources for required tags.

This project creates test Azure resources with Terraform, then uses the Azure SDK for Python to find resources missing these tags:

- `owner`
- `environment`

It also supports:

- A readable terminal report
- JSON report output
- A dry-run remediation preview
- An optional remediation action that adds `environment=unknown`

> `owner` is never auto-fixed because the script should not guess who owns a resource.

---

## What This Project Teaches

```text
Azure CLI login
    ↓
Terraform creates test resources
    ↓
DefaultAzureCredential reuses the Azure CLI session
    ↓
Python discovers subscription resources
    ↓
Python checks resource tags
    ↓
Python collects violations
    ↓
Text report + JSON report
    ↓
Optional dry-run or remediation
```

This mirrors a real cloud governance workflow:

```text
Discover → Inspect → Collect findings → Report → Remediate safely
```

---

## Project Structure

```text
azure-test-env/
├── .venv/              # Local Python virtual environment
├── main.tf              # Terraform test environment
├── tag_auditor.py      # Python auditor
├── terraform.tfstate   # Terraform state; do not commit this
└── README.md
```

The `.venv` directory contains project-specific Python and installed libraries.

---

## Requirements

Install these tools first:

- Azure CLI
- Terraform
- Python 3
- Git Bash, PowerShell, or another terminal
- An Azure subscription where you can create resources

You need permission to create and update storage accounts. `Contributor` on the resource group is usually enough.

---

# Part 1: Azure CLI Setup on Windows and Git Bash

## Question: How do I install Azure CLI when using Windows with Git Bash?

Install Azure CLI from **Windows PowerShell**, not through the Linux installer.

Open PowerShell and run:

```powershell
winget install --exact --id Microsoft.AzureCLI
```

If `winget` is unavailable, download the Windows installer here:

```text
https://aka.ms/installazurecliwindows
```

After installation, close and reopen Git Bash.

Verify the install:

```bash
az version
```

Sign in:

```bash
az login
```

Check your active subscription:

```bash
az account show
```

Get only the subscription ID:

```bash
az account show --query id -o tsv
```

---

# Part 2: Terraform Test Environment

## Why create test resources?

The Python auditor needs actual Azure resources to inspect.

Terraform creates:

1. A resource group with both required tags.
2. A compliant storage account with both required tags.
3. A non-compliant storage account missing tags.

The non-compliant account gives the auditor something deliberate to find.

---

## `main.tf`

Create a file named `main.tf`:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Stops Terraform from trying to register many unrelated Azure providers.
  resource_provider_registrations = "none"
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "audit_lab" {
  name     = "rg-tag-auditor-lab"
  location = "eastus"

  tags = {
    owner       = "your-name"
    environment = "dev"
  }
}

resource "azurerm_storage_account" "compliant" {
  name                     = "tagauditgood${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.audit_lab.name
  location                 = azurerm_resource_group.audit_lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    owner       = "your-name"
    environment = "dev"
  }
}

resource "azurerm_storage_account" "missing_environment" {
  name                     = "tagauditbad${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.audit_lab.name
  location                 = azurerm_resource_group.audit_lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    owner = "your-name"
  }
}
```

---

## Question: What is `Microsoft.Storage`, and why is it needed?

`Microsoft.Storage` is an Azure resource provider.

Resource providers are Azure service categories:

```text
Microsoft.Storage   → Storage accounts, blobs, queues, files
Microsoft.Compute   → Virtual machines
Microsoft.Network   → Virtual networks, load balancers, public IPs
Microsoft.KeyVault  → Azure Key Vaults
```

Because this Terraform project creates `azurerm_storage_account` resources, Azure must have the storage provider registered for the subscription.

Register it:

```bash
az provider register --namespace Microsoft.Storage
```

Check registration status:

```bash
az provider show \
  --namespace Microsoft.Storage \
  --query registrationState \
  -o tsv
```

Wait until the output is:

```text
Registered
```

Registering a provider does not create billable resources. It only allows the subscription to use that Azure service category.

---

## Question: What does this Terraform setting mean?

```hcl
resource_provider_registrations = "none"
```

This tells Terraform:

> Do not automatically register Azure resource providers.

Without this setting, Terraform may try to register many unrelated providers, such as:

```text
Microsoft.KeyVault
Microsoft.ContainerRegistry
Microsoft.Compute
Microsoft.EventGrid
Microsoft.ServiceFabric
```

For this project, only `Microsoft.Storage` is needed.

---

## Error: Terraform tried registering many providers and showed `context canceled`

Example:

```text
waiting for Subscription Provider ... to be registered: context canceled
```

### Cause

Terraform was trying to register many Azure service providers. The command was canceled, timed out, or took too long.

### Fix

Add this to the `azurerm` provider configuration:

```hcl
resource_provider_registrations = "none"
```

Then register only the storage provider:

```bash
az provider register --namespace Microsoft.Storage
```

---

## Question: Do I need to run `terraform init` again after changing the provider configuration?

Yes.

Run:

```bash
terraform init
```

Then create a plan:

```bash
terraform plan
```

Then deploy:

```bash
terraform apply
```

Type `yes` when Terraform asks for confirmation.

---

## Terraform Plan Diagram

```text
terraform plan
│
├─ Reads main.tf
│
├─ Compares declared resources with Terraform state
│
└─ Proposes changes
   │
   ├─ + random_string.suffix
   │    └─ Creates an 8-character suffix
   │
   ├─ + azurerm_resource_group.audit_lab
   │    └─ Creates rg-tag-auditor-lab
   │       tags:
   │       ├─ owner = your-name
   │       └─ environment = dev
   │
   ├─ + azurerm_storage_account.compliant
   │    └─ Creates a fully tagged storage account
   │       tags:
   │       ├─ owner = your-name
   │       └─ environment = dev
   │
   └─ + azurerm_storage_account.missing_environment
        └─ Creates an intentionally non-compliant account
           tags:
           └─ owner = your-name
              ❌ environment is missing
```

A plan summary like this is expected:

```text
Plan: 4 to add, 0 to change, 0 to destroy.
```

The `+` means Terraform will create the resource.

---

## Question: Why do storage account names need a suffix?

Azure storage account names must be globally unique across all Azure customers.

This may already exist:

```text
tagauditgood12345
```

Terraform uses a random suffix to avoid collisions:

```text
tagauditgood + a7k2m9pq
= tagauditgooda7k2m9pq
```

The `random_string` resource creates that suffix.

---

# Part 3: Python Virtual Environment

## Question: Where should I create the virtual environment?

Create it in the project root: the same folder that contains `main.tf`.

Example:

```bash
cd "/c/Users/your-user/OneDrive - Dell Technologies/Desktop/New folder (9)/azure-test-env"
```

Create the environment:

```bash
python -m venv .venv
```

Because this project uses **Git Bash on Windows**, activate it with:

```bash
source .venv/Scripts/activate
```

Your prompt should begin with:

```text
(.venv)
```

---

## Question: What if I am inside `.venv` already?

Move back to the project root:

```bash
cd ..
```

Then activate the environment:

```bash
source .venv/Scripts/activate
```

Your files should be arranged like this:

```text
azure-test-env/
├── .venv/
├── main.tf
└── tag_auditor.py
```

Do not put `main.tf` or `tag_auditor.py` inside `.venv`.

---

## Question: Do installed libraries disappear after I close Git Bash?

No.

Installed packages remain inside `.venv` until you delete `.venv`.

Closing the terminal only deactivates the environment.

The next time you work on this project:

```bash
cd "/path/to/azure-test-env"
source .venv/Scripts/activate
```

---

## Question: Can outside folders access libraries in this `.venv`?

Not automatically.

A virtual environment acts like a dependency barrier:

```text
azure-test-env/.venv/
    └─ Azure SDK packages for this project

another-project/.venv/
    └─ That project's own packages
```

This is dependency isolation, not a security barrier.

---

## Install Python Dependencies

With `(.venv)` active, install the Azure SDK packages:

```bash
python -m pip install --upgrade azure-identity azure-mgmt-resource
```

Set the subscription ID for the current Git Bash session:

```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

Check it:

```bash
echo "$AZURE_SUBSCRIPTION_ID"
```

---

# Part 4: Python Azure Tag Auditor

## Initial Import Error

### Error

```text
ImportError: cannot import name 'ResourceManagementClient'
from 'azure.mgmt.resource'
```

### Cause

With `azure-mgmt-resource` version `26.0.0`, `azure.mgmt.resource` is a namespace package.

This import does not work with that package layout:

```python
from azure.mgmt.resource import ResourceManagementClient
```

### Fix

Use:

```python
from azure.mgmt.resource.resources import ResourceManagementClient
```

Test it:

```bash
python -c "from azure.mgmt.resource.resources import ResourceManagementClient; print('Import worked')"
```

Expected output:

```text
Import worked
```

---

## Resource Group Attribute Error

### Error

```text
AttributeError: 'GenericResourceExpanded' object has no attribute 'resource_group'
```

### Cause

Resources returned by this SDK listing do not have a `.resource_group` attribute.

Azure resource IDs contain the resource group:

```text
/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/...
```

### Fix

Parse the resource group from the Azure resource ID.

```python
def get_resource_group(resource_id):
    parts = resource_id.split("/")

    for index, part in enumerate(parts):
        if part.lower() == "resourcegroups":
            return parts[index + 1]

    return None
```

Use:

```python
get_resource_group(resource.id)
```

instead of:

```python
resource.resource_group
```

---

## API Version Attribute Error

### Error

```text
AttributeError: 'GenericResourceExpanded' object has no attribute 'api_version'
```

### Cause

The generic resource object does not include an API version.

The first attempted remediation used a generic resource update call that required one.

### Fix

Use Azure’s tag API instead:

```python
resource_client.tags.begin_update_at_scope(...)
```

The `Merge` operation updates only the requested tag instead of replacing all tags.

---

# Final `tag_auditor.py`

Create or replace `tag_auditor.py` with this code:

```python
import argparse
import json
import os

from azure.identity import DefaultAzureCredential
from azure.mgmt.resource.resources import ResourceManagementClient


REQUIRED_TAGS = ["owner", "environment"]


def get_arguments():
    parser = argparse.ArgumentParser(
        description="Audit Azure resources for required tags."
    )

    fix_group = parser.add_mutually_exclusive_group()

    fix_group.add_argument(
        "--fix",
        action="store_true",
        help="Dry run: show resources that would receive environment=unknown.",
    )

    fix_group.add_argument(
        "--apply-fix",
        action="store_true",
        help="Add environment=unknown to resources missing that tag.",
    )

    return parser.parse_args()


def find_missing_tags(tags):
    tags = tags or {}
    return [tag for tag in REQUIRED_TAGS if not tags.get(tag)]


def get_resource_group(resource_id):
    parts = resource_id.split("/")

    for index, part in enumerate(parts):
        if part.lower() == "resourcegroups":
            return parts[index + 1]

    return None


def main():
    args = get_arguments()
    subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]

    credential = DefaultAzureCredential()
    resource_client = ResourceManagementClient(credential, subscription_id)

    resource_groups = list(resource_client.resource_groups.list())

    findings = []
    resources_missing_environment = []
    missing_owner_count = 0
    missing_environment_count = 0
    total_resources_scanned = 0

    # The Azure SDK handles paginated resource-list responses.
    for resource in resource_client.resources.list():
        total_resources_scanned += 1
        missing_tags = find_missing_tags(resource.tags)

        if "owner" in missing_tags:
            missing_owner_count += 1

        if "environment" in missing_tags:
            missing_environment_count += 1
            resources_missing_environment.append(resource)

        if missing_tags:
            findings.append(
                {
                    "name": resource.name,
                    "type": resource.type,
                    "resource_group": get_resource_group(resource.id),
                    "missing_tags": missing_tags,
                }
            )

    report = {
        "resource_groups_found": len(resource_groups),
        "total_resources_scanned": total_resources_scanned,
        "missing_owner_count": missing_owner_count,
        "missing_environment_count": missing_environment_count,
        "offenders": findings,
    }

    print("Azure Tag Audit Report")
    print("=" * 40)
    print(f"Resource groups found: {report['resource_groups_found']}")
    print(f"Resources scanned: {report['total_resources_scanned']}")
    print(f"Resources missing owner: {report['missing_owner_count']}")
    print(f"Resources missing environment: {report['missing_environment_count']}")

    if findings:
        print("\nOffenders:")

        for finding in findings:
            missing = ", ".join(finding["missing_tags"])

            print(
                f"- {finding['name']} "
                f"({finding['type']}) "
                f"in {finding['resource_group']}: "
                f"missing {missing}"
            )
    else:
        print("\nNo tag violations found.")

    print("\nJSON report:")
    print(json.dumps(report, indent=2))

    if args.fix:
        print("\nDry-run remediation:")

        if not resources_missing_environment:
            print("No resources need an environment tag.")

        for resource in resources_missing_environment:
            print(
                f"Would add environment=unknown to "
                f"{resource.name} in {get_resource_group(resource.id)}"
            )

    if args.apply_fix:
        print("\nApplying remediation:")

        if not resources_missing_environment:
            print("No resources need an environment tag.")

        for resource in resources_missing_environment:
            resource_client.tags.begin_update_at_scope(
                scope=resource.id,
                parameters={
                    "operation": "Merge",
                    "properties": {
                        "tags": {
                            "environment": "unknown"
                        }
                    },
                },
            ).result()

            print(
                f"Added environment=unknown to "
                f"{resource.name} in {get_resource_group(resource.id)}"
            )


if __name__ == "__main__":
    main()
```

---

# Running the Auditor

## Normal Audit

Run:

```bash
python tag_auditor.py
```

This performs:

```text
Discover resources
    ↓
Check owner and environment tags
    ↓
Collect findings
    ↓
Print report
    ↓
Print JSON
```

It does not change Azure.

---

## Dry Run

Run:

```bash
python tag_auditor.py --fix
```

This performs the regular audit and then prints what it would change.

Example:

```text
Dry-run remediation:
Would add environment=unknown to tagauditbadXXXXXXXX in rg-tag-auditor-lab
```

`--fix` is only a preview. It does not modify Azure.

---

## Apply the Fix

Run this only after reviewing dry-run output:

```bash
python tag_auditor.py --apply-fix
```

This adds:

```text
environment = unknown
```

to every resource missing the `environment` tag.

The script uses:

```python
"operation": "Merge"
```

`Merge` preserves existing tags and adds or updates only `environment`.

For example, if a resource currently has:

```json
{
  "owner": "platform"
}
```

after remediation it becomes:

```json
{
  "owner": "platform",
  "environment": "unknown"
}
```

---

## Question: What happens if both `owner` and `environment` are missing?

The resource is still included in dry-run and remediation because it is missing `environment`.

Example audit result:

```text
missing owner, environment
```

Example dry-run result:

```text
Would add environment=unknown to tagauditbadXXXXXXXX in rg-tag-auditor-lab
```

After applying the fix:

```text
environment = unknown
```

will exist, but `owner` remains missing.

This is intentional. The script should not invent an ownership value.

---

# Expected Outputs

## Before Remediation

If the bad storage account is missing both tags:

```text
Azure Tag Audit Report
========================================
Resource groups found: 1
Resources scanned: 2
Resources missing owner: 1
Resources missing environment: 1

Offenders:
- tagauditbadXXXXXXXX (Microsoft.Storage/storageAccounts)
  in rg-tag-auditor-lab: missing owner, environment
```

Expected JSON shape:

```json
{
  "resource_groups_found": 1,
  "total_resources_scanned": 2,
  "missing_owner_count": 1,
  "missing_environment_count": 1,
  "offenders": [
    {
      "name": "tagauditbadXXXXXXXX",
      "type": "Microsoft.Storage/storageAccounts",
      "resource_group": "rg-tag-auditor-lab",
      "missing_tags": [
        "owner",
        "environment"
      ]
    }
  ]
}
```

---

## After `--apply-fix`

Run:

```bash
python tag_auditor.py
```

Expected results:

```text
Resources missing owner: 1
Resources missing environment: 0
```

The bad storage account is still an offender because `owner` is missing.

---

# Why Terraform Shows So Many Storage Account Properties

## Question

Why does Terraform show many properties when deleting a storage account?

Example:

```text
access_tier = "Hot" -> null
https_traffic_only_enabled = true -> null
primary_blob_endpoint = "https://..." -> null
primary_access_key = (sensitive value) -> null
```

## Answer

Terraform is showing a **storage account**, not a resource group.

You define only a few settings in `main.tf`:

```hcl
name
resource_group_name
location
account_tier
account_replication_type
tags
```

Azure fills in many others automatically.

Those properties come from three places:

```text
Your Terraform configuration       Azure defaults             Azure-generated values
────────────────────────────       ──────────────             ─────────────────────
name                               HTTPS enabled              resource ID
location                           TLS 1.2                    endpoint URLs
Standard tier                      StorageV2                  access keys
LRS replication                    Hot access tier            connection strings
tags                               public network access
```

Terraform reads Azure’s response after deployment and stores the known state in:

```text
terraform.tfstate
```

During destruction:

```text
value -> null
```

means:

> This property exists now, but it will no longer exist after Terraform deletes the resource.

---

# Terraform Drift

The Python script can update Azure tags outside Terraform.

For example, `--apply-fix` adds:

```text
environment = unknown
```

Terraform did not make that specific change.

When Terraform refreshes state, it can see the updated Azure tags. This is called **configuration drift**.

```text
Terraform configuration
    ≠
Actual Azure resource settings
```

In this project, drift is intentional because it demonstrates how an auditor and remediation script can modify infrastructure outside Terraform.

In a production setup, teams often choose one of these approaches:

1. Make Terraform the only tool allowed to modify infrastructure.
2. Update Terraform code after a remediation tool changes resources.
3. Use policy-as-code tools that report violations but do not modify resources.
4. Import or refresh Azure changes into Terraform state and review them.

---

# Useful Commands

## Verify Azure login

```bash
az account show
```

## Show resources and their tags

```bash
az resource list \
  --query "[].{name:name,group:resourceGroup,type:type,tags:tags}" \
  -o table
```

## Re-run Terraform plan

```bash
terraform plan
```

## Apply Terraform configuration

```bash
terraform apply
```

## Run the audit

```bash
python tag_auditor.py
```

## Preview environment remediation

```bash
python tag_auditor.py --fix
```

## Apply environment remediation

```bash
python tag_auditor.py --apply-fix
```

## Destroy all practice resources

```bash
terraform destroy
```

---

# Cleanup

When you finish the exercise, remove the Azure resources:

```bash
terraform destroy
```

Type `yes` when prompted.

If you are finished with the local Python environment too, deactivate it:

```bash
deactivate
```

You can delete `.venv` later if you want. That removes only the project’s installed Python libraries.

---

# Key Takeaways

```text
Terraform creates repeatable cloud test resources.

Azure Resource Providers must be registered before using a service.

DefaultAzureCredential can reuse an Azure CLI login locally.

Virtual environments isolate Python dependencies per project.

Azure SDK resource listings can be paginated.

Azure resource IDs contain metadata such as the resource group.

A tag auditor should separate discovery, validation, reporting, and remediation.

Dry-run behavior should come before destructive or modifying actions.

Tag merges are safer than replacing all tags.

Terraform can detect Azure-side changes made by other tools.
```