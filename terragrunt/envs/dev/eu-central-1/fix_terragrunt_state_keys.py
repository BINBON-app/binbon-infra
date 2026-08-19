#!/usr/bin/env python3

from pathlib import Path
import re
import sys


# Run this script from:
# terragrunt/envs/dev/eu-central-1
#
# It updates all Terragrunt component files under:
# ../../../components
#
# It replaces:
#   key = "${path_relative_to_include()}/terraform.tfstate"
#
# with:
#   key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate"


COMPONENTS_DIR = Path("../../../components")

OLD_KEY_PATTERN = re.compile(
    r'key\s*=\s*"\$\{path_relative_to_include\(\)\}/terraform\.tfstate"'
)

NEW_KEY = (
    'key = "${local.env.locals.environment}/'
    '${local.env.locals.region}/'
    '${basename(get_original_terragrunt_dir())}/terraform.tfstate"'
)


def patch_file(path: Path) -> str:
    text = path.read_text(encoding="utf-8")

    # Already fixed
    if NEW_KEY in text:
        return "skip"

    new_text, count = OLD_KEY_PATTERN.subn(
        NEW_KEY,
        text,
        count=1,
    )

    if count == 0:
        return "not-found"

    path.write_text(new_text, encoding="utf-8")
    return "updated"


def main():
    if not COMPONENTS_DIR.exists():
        print()
        print("ERROR: Components directory not found:")
        print(f"  {COMPONENTS_DIR.resolve()}")
        print()
        print("Run this script from:")
        print("  terragrunt/envs/dev/eu-central-1")
        print()
        sys.exit(1)

    hcl_files = sorted(COMPONENTS_DIR.glob("*.hcl"))

    if not hcl_files:
        print()
        print(f"ERROR: No .hcl files found in: {COMPONENTS_DIR.resolve()}")
        print()
        sys.exit(1)

    print()
    print("Terragrunt S3 state-key patch")
    print("=" * 60)
    print(f"Components directory: {COMPONENTS_DIR.resolve()}")
    print()

    updated = 0
    skipped = 0
    not_found = 0

    for path in hcl_files:
        result = patch_file(path)

        if result == "updated":
            print(f"[UPDATED]   {path}")
            updated += 1

        elif result == "skip":
            print(f"[SKIP]      {path} already has the corrected state key")
            skipped += 1

        else:
            print(f"[NO MATCH]  {path}")
            not_found += 1

    print()
    print("=" * 60)
    print(f"Updated:  {updated}")
    print(f"Skipped:  {skipped}")
    print(f"No match: {not_found}")
    print()

    print("Expected backend key format:")
    print()
    print(
        '  ${local.env.locals.environment}/'
        '${local.env.locals.region}/'
        '${basename(get_original_terragrunt_dir())}/terraform.tfstate'
    )
    print()

    print("Next commands:")
    print()
    print("  terragrunt hcl fmt")
    print()
    print("  grep -R 'path_relative_to_include' ../../../components")
    print()
    print("  terragrunt hcl validate --show-config-path")
    print()
    print('  find . -type d -name ".terragrunt-cache" -prune -exec rm -rf {} +')
    print()
    print("  terragrunt run --all init")
    print()


if __name__ == "__main__":
    main()