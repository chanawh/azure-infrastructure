# Azure Terraform Reusable Network Module

This project builds a reusable Azure network module with Terraform.

It creates an Azure Virtual Network and named subnets.  
The module validates CIDR input before Azure deployment and returns stable IDs for consumers.

## Learning Goals

- Build a reusable Terraform module for Azure networking.
- Use typed variables for module inputs.
- Reject malformed CIDR ranges during `terraform plan`.
- Return VNet and subnet IDs as stable module outputs.
- Reuse one module for dev and prod without editing module code.
- Keep environment-specific values in environment configurations.

---

## Project Structure

```text
azure-network-module/
├── .gitignore
├── README.md
└── terraform/
    ├── modules/
    │   └── network/
    │       ├── main.tf
    │       ├── variables.tf
    │       ├── outputs.tf
    │       └── versions.tf
    │
    └── environments/
        ├── dev/
        │   ├── main.tf
        │   └── versions.tf
        │
        └── prod/
            ├── main.tf
            └── versions.tf
```

---

## Architecture

```text
┌──────────────────────────┐
│ environments/dev/main.tf │
│ environments/prod/main.tf│
└────────────┬─────────────┘
             │
             │ Passes environment-specific inputs:
             │ - resource group name
             │ - location
             │ - VNet name
             │ - CIDR ranges
             │ - subnet definitions
             ▼
┌────────────────────────────────────────┐
│        modules/network                 │
│                                        │
│ variables.tf                           │
│   - typed inputs                       │
│   - CIDR validation                    │
│                                        │
│ main.tf                                │
│   - Azure VNet                         │
│   - Azure subnets                      │
│                                        │
│ outputs.tf                             │
│   - vnet_id                            │
│   - subnet_ids                         │
└────────────┬───────────────────────────┘
             │
             ▼
┌────────────────────────────────────────┐
│ Azure Resource Group                    │
│ Azure Virtual Network                   │
│ Azure Subnets: app, data                │
└────────────────────────────────────────┘
```

---

## Prerequisites

Install these tools before running the project:

- Terraform `1.5.0` or newer
- Azure CLI
- Git
- An Azure subscription
- Permission to create resource groups, VNets, and subnets

Check installed versions:

```bash
terraform version
az version
git --version
```

---

## Azure Authentication

Terraform uses your Azure CLI login session.

Sign in with Microsoft Graph scope:

```bash
az login --scope https://graph.microsoft.com/.default
```

List subscriptions available to your account:

```bash
az account list --output table
```

Set the subscription Terraform should use:

```bash
az account set --subscription "<subscription-name-or-id>"
```

Confirm the active subscription:

```bash
az account show --output table
```

---

## Module Design

The network module has a public interface made of variables and outputs.

```text
Public module inputs:
- resource_group_name
- location
- vnet_name
- address_space
- subnets

Private implementation:
- azurerm_virtual_network.this
- azurerm_subnet.this

Public module outputs:
- vnet_id
- subnet_ids
```

Consumers should use module outputs:

```hcl
module.network.vnet_id
module.network.subnet_ids["app"]
```

Consumers should not access module resources directly:

```hcl
# Do not reference this from an environment configuration
azurerm_subnet.this["app"].id
```

This keeps the internal resource labels private.  
The module can change internally while consumers keep the same output contract.

---

## CIDR Validation

The module checks CIDR values before Terraform tries to create Azure resources.

Example validation:

```hcl
validation {
  condition = alltrue([
    for cidr in var.address_space : can(cidrhost(cidr, 0))
  ])

  error_message = "Every address_space entry must be a valid CIDR, such as 10.20.0.0/16."
}
```

A valid CIDR looks like this:

```hcl
address_space = ["10.20.0.0/16"]
```

An invalid CIDR looks like this:

```hcl
address_space = ["not-a-cidr"]
```

---

## Deploy Development

Move into the dev Terraform root configuration:

```bash
cd terraform/environments/dev
```

Initialize Terraform:

```bash
terraform init
```

Format all Terraform files:

```bash
terraform fmt -recursive
```

Validate Terraform syntax and module references:

```bash
terraform validate
```

Preview resources Terraform plans to create:

```bash
terraform plan
```

Create the dev resources:

```bash
terraform apply
```

Type `yes` when Terraform asks for confirmation.

View outputs after deployment:

```bash
terraform output
terraform output app_subnet_id
```

---

## Deploy Production

Move into the production Terraform root configuration:

```bash
cd terraform/environments/prod
```

Run the Terraform workflow:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Dev and prod both reference the same reusable module:

```hcl
source = "../../modules/network"
```

Dev and prod differ only by values passed to that module.

Example dev CIDR:

```hcl
address_space = ["10.20.0.0/16"]
```

Example production CIDR:

```hcl
address_space = ["10.30.0.0/16"]
```

---

## Test CIDR Validation

To test validation, edit either environment's `main.tf`.

For example, in `terraform/environments/prod/main.tf`:

```hcl
address_space = [
  "not-a-cidr"
]
```

Run:

```bash
terraform plan
```

Terraform should fail with a message similar to:

```text
Every address_space entry must be a valid CIDR, such as 10.20.0.0/16.
```

This is expected. It proves bad input fails before Azure resource creation.

Restore the valid CIDR before applying:

```hcl
address_space = [
  "10.30.0.0/16"
]
```

---

## Module Outputs

The module returns only values consumers need.

Example outputs:

```hcl
output "vnet_id" {
  description = "Azure resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Subnet IDs keyed by subnet name."

  value = {
    for name, subnet in azurerm_subnet.this : name => subnet.id
  }
}
```

The output shape looks like this:

```hcl
subnet_ids = {
  app  = "/subscriptions/.../subnets/app"
  data = "/subscriptions/.../subnets/data"
}
```

A consumer can select the `app` subnet ID:

```hcl
subnet_id = module.network.subnet_ids["app"]
```

An AKS cluster could use that ID in its network configuration.

---

## Terraform State

Each environment is a separate Terraform root configuration.

```text
terraform/environments/dev
terraform/environments/prod
```

Each directory has its own Terraform state.

```text
dev  -> manages dev resources
prod -> manages prod resources
```

Run `terraform init`, `terraform plan`, `terraform apply`, and `terraform destroy` from an environment directory.

Do not run `terraform apply` or `terraform destroy` from:

```text
terraform/modules/network
```

That directory contains reusable module code. It does not own an environment state file.

---

## Destroy Resources

Destroy production resources from the production directory:

```bash
cd terraform/environments/prod
terraform plan -destroy
terraform destroy
```

Type `yes` when asked for confirmation.

Destroy dev resources from the dev directory:

```bash
cd ../dev
terraform plan -destroy
terraform destroy
```

Destroying prod does not destroy dev.  
Each environment has separate state and separate Azure resources.

---

## Issues Encountered and Fixes

### Azure CLI authentication blocked by Security Defaults

Error:

```text
AADSTS530035: Access has been blocked by security defaults.
Interactive authentication is needed.
```

Fix:

```bash
az login --scope https://graph.microsoft.com/.default
```

Then list subscriptions:

```bash
az account list --output table
```

Set the correct subscription:

```bash
az account set --subscription "<subscription-name-or-id>"
```

Retry Terraform:

```bash
terraform plan
```

---

### Invalid CIDR validation error

Error:

```text
Every address_space entry must be a valid CIDR, such as 10.20.0.0/16.
```

Cause:

```hcl
address_space = ["not-a-cidr"]
```

Fix:

```hcl
address_space = ["10.30.0.0/16"]
```

This error is expected when testing module validation.

---

### Terraform command run from the wrong directory

Run Terraform commands from one of these directories:

```text
terraform/environments/dev
terraform/environments/prod
```

Correct usage:

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

Do not run deployment commands inside:

```text
terraform/modules/network
```

---

### Wrong Azure subscription selected

Check the currently selected subscription:

```bash
az account show --output table
```

Set the intended subscription:

```bash
az account set --subscription "<subscription-name-or-id>"
```

Then rerun:

```bash
terraform plan
```

---

## Git Best Practices

Commit Terraform code, documentation, and the provider lock file.

Keep this file tracked:

```text
.terraform.lock.hcl
```

Do not commit Terraform state files, credentials, `.tfvars` files containing secrets, or provider downloads.

Example `.gitignore`:

```gitignore
# Terraform provider downloads
**/.terraform/*

# Terraform state files
*.tfstate
*.tfstate.*
*.tfstate.backup

# Terraform crash logs
crash.log
crash.*.log

# Variable files that may contain secrets
*.tfvars
*.tfvars.json

# Terraform override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Terraform CLI configuration
.terraformrc
terraform.rc

# Local environment files
.env
.env.*

# IDE and OS files
.vscode/
.idea/
.DS_Store
Thumbs.db
```

Check files before committing:

```bash
git status
```

Add the project files:

```bash
git add .
```

Create a commit:

```bash
git commit -m "Add reusable Azure network Terraform module"
```

---

## Recommended Improvements

- Store Terraform state remotely in Azure Storage.
- Use state locking for team deployments.
- Add resource tags such as `environment`, `owner`, and `project`.
- Add Network Security Groups for subnet rules.
- Add private endpoints for Azure PaaS services.
- Create an AKS module that consumes `subnet_ids["app"]`.
- Add GitHub Actions for `terraform fmt -check` and `terraform validate`.
- Use workload identity federation for CI/CD authentication.
- Add unit or integration checks with `terraform test`.

---

## Key Takeaways

- Terraform modules should have small and stable public interfaces.
- Typed variables make invalid module input easier to catch.
- CIDR validation stops malformed input during planning.
- Outputs should expose IDs and maps rather than resource internals.
- Dev and prod should reuse the same module code.
- Environment differences belong in environment configuration files.
- Run Terraform commands from the environment directory that owns the state.