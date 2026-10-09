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