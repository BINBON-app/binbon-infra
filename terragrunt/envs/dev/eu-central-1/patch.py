#!/usr/bin/env python3

from pathlib import Path
import re
import sys


# Run this script from:
# terragrunt/envs/dev/eu-central-1
#
# Expected components path:
# ../../../components


COMPONENTS_DIR = Path("../../../components")


def add_backend_generate_block(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")

    # Skip files already configured to generate backend.tf
    if re.search(
        r'generate\s*=\s*\{[^}]*path\s*=\s*"backend\.tf"',
        text,
        flags=re.DOTALL,
    ):
        print(f"[SKIP]    {path} already generates backend.tf")
        return False

    pattern = re.compile(
        r'(\bbackend\s*=\s*"s3"\s*)',
        flags=re.MULTILINE,
    )

    replacement = (
        r'\1'
        '\n\n'
        '  generate = {\n'
        '    path      = "backend.tf"\n'
        '    if_exists = "overwrite_terragrunt"\n'
        '  }\n'
    )

    new_text, count = pattern.subn(
        replacement,
        text,
        count=1,
    )

    if count == 0:
        print(f'[WARNING] {path} does not contain backend = "s3"')
        return False

    path.write_text(new_text, encoding="utf-8")
    print(f"[UPDATED] {path}")
    return True


def main():
    if not COMPONENTS_DIR.exists():
        print()
        print("ERROR: Components directory was not found:")
        print(f"  {COMPONENTS_DIR.resolve()}")
        print()
        print("Run this script from:")
        print("  terragrunt/envs/dev/eu-central-1")
        print()
        sys.exit(1)

    hcl_files = sorted(COMPONENTS_DIR.glob("*.hcl"))

    if not hcl_files:
        print(f"ERROR: No .hcl files found in {COMPONENTS_DIR}")
        sys.exit(1)

    print()
    print("Terragrunt backend.tf generator patch")
    print("=" * 45)
    print(f"Components directory: {COMPONENTS_DIR.resolve()}")
    print()

    updated = 0
    unchanged = 0

    for path in hcl_files:
        if add_backend_generate_block(path):
            updated += 1
        else:
            unchanged += 1

    print()
    print("=" * 45)
    print(f"Updated:   {updated}")
    print(f"Unchanged: {unchanged}")
    print()

    print("Next commands:")
    print()
    print("  terragrunt hcl fmt")
    print("  terragrunt hcl validate --show-config-path")
    print()
    print('  grep -R "REPLACE_AFTER_BOOTSTRAP" ../../../components ../../../root.hcl')
    print()
    print('  find . -type d -name ".terragrunt-cache" -prune -exec rm -rf {} +')
    print()
    print("  terragrunt run --all init")
    print()


if __name__ == "__main__":
    main()