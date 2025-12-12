#!/usr/bin/env python3
"""
OpenAlex Data Integrity Checker
Purpose: Verify data consistency between source files and Parquet files
Author: Senior Data Engineer
Date: 2025-12-12
"""

import os
import sys
import glob
from pathlib import Path
from collections import defaultdict

# Project configuration
PROJECT_ROOT = Path(__file__).parent.parent
SOURCE_DIR = PROJECT_ROOT / "data" / "source"
PARQUET_DIR = PROJECT_ROOT / "data" / "parquet"

# Entity types
ENTITY_TYPES = [
    "authors", "concepts", "domains", "fields", "funders",
    "institutions", "publishers", "sources", "subfields", "topics", "works"
]

# ANSI color codes
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
BOLD = '\033[1m'
NC = '\033[0m'  # No Color


def print_header(text):
    """Print a formatted header."""
    print(f"\n{BOLD}{BLUE}{'='*80}{NC}")
    print(f"{BOLD}{BLUE}{text}{NC}")
    print(f"{BOLD}{BLUE}{'='*80}{NC}\n")


def print_success(text):
    """Print success message."""
    print(f"{GREEN}✓ {text}{NC}")


def print_warning(text):
    """Print warning message."""
    print(f"{YELLOW}⚠ {text}{NC}")


def print_error(text):
    """Print error message."""
    print(f"{RED}✗ {text}{NC}")


def check_orphan_parquets():
    """Check for Parquet files without corresponding source files."""
    print_header("CHECKING FOR ORPHAN PARQUET FILES")

    total_orphans = 0
    orphans_by_entity = defaultdict(list)

    for entity_type in ENTITY_TYPES:
        parquet_pattern = str(PARQUET_DIR / entity_type / "**" / "*.parquet")
        parquet_files = glob.glob(parquet_pattern, recursive=True)

        if not parquet_files:
            continue

        print(f"\nChecking {entity_type}: {len(parquet_files)} Parquet files...")

        for parquet_file in parquet_files:
            # Derive source file path
            rel_path = os.path.relpath(parquet_file, PARQUET_DIR)
            source_rel_path = rel_path.replace(".parquet", ".gz")
            source_file = SOURCE_DIR / source_rel_path

            if not source_file.exists():
                orphans_by_entity[entity_type].append(rel_path)
                total_orphans += 1

    print(f"\n{'-'*80}")
    if total_orphans == 0:
        print_success(f"No orphan Parquet files found!")
    else:
        print_error(f"Found {total_orphans} orphan Parquet files:")
        for entity, orphans in orphans_by_entity.items():
            print(f"\n  {entity}: {len(orphans)} orphans")
            for orphan in orphans[:5]:  # Show first 5
                print(f"    - {orphan}")
            if len(orphans) > 5:
                print(f"    ... and {len(orphans) - 5} more")

    return total_orphans


def check_missing_parquets():
    """Check for source files without corresponding Parquet files."""
    print_header("CHECKING FOR MISSING PARQUET FILES")

    total_missing = 0
    missing_by_entity = defaultdict(list)

    for entity_type in ENTITY_TYPES:
        source_pattern = str(SOURCE_DIR / entity_type / "**" / "*.gz")
        source_files = glob.glob(source_pattern, recursive=True)

        if not source_files:
            continue

        print(f"\nChecking {entity_type}: {len(source_files)} source files...")

        for source_file in source_files:
            # Derive Parquet file path
            rel_path = os.path.relpath(source_file, SOURCE_DIR)
            parquet_rel_path = rel_path.replace(".gz", ".parquet")
            parquet_file = PARQUET_DIR / parquet_rel_path

            if not parquet_file.exists():
                missing_by_entity[entity_type].append(rel_path)
                total_missing += 1

    print(f"\n{'-'*80}")
    if total_missing == 0:
        print_success("All source files have corresponding Parquet files!")
    else:
        print_warning(f"Found {total_missing} source files without Parquet:")
        for entity, missing in missing_by_entity.items():
            print(f"\n  {entity}: {len(missing)} missing")
            for miss in missing[:5]:  # Show first 5
                print(f"    - {miss}")
            if len(missing) > 5:
                print(f"    ... and {len(missing) - 5} more")
        print(f"\n  {YELLOW}Note: Run ETL to process these files{NC}")

    return total_missing


def check_file_counts():
    """Compare file counts between source and Parquet."""
    print_header("FILE COUNT COMPARISON")

    print(f"{'Entity':<15} {'Source Files':<15} {'Parquet Files':<15} {'Status'}")
    print(f"{'-'*60}")

    total_issues = 0

    for entity_type in ENTITY_TYPES:
        source_pattern = str(SOURCE_DIR / entity_type / "**" / "*.gz")
        source_files = glob.glob(source_pattern, recursive=True)
        source_count = len(source_files)

        parquet_pattern = str(PARQUET_DIR / entity_type / "**" / "*.parquet")
        parquet_files = glob.glob(parquet_pattern, recursive=True)
        parquet_count = len(parquet_files)

        if source_count == 0 and parquet_count == 0:
            continue

        if source_count == parquet_count:
            status = f"{GREEN}✓ Match{NC}"
        elif parquet_count > source_count:
            status = f"{RED}✗ Extra Parquet{NC}"
            total_issues += 1
        else:
            status = f"{YELLOW}⚠ Missing Parquet{NC}"
            total_issues += 1

        print(f"{entity_type:<15} {source_count:<15} {parquet_count:<15} {status}")

    print(f"\n{'-'*80}")
    if total_issues == 0:
        print_success("All entity types have matching file counts!")
    else:
        print_warning(f"Found {total_issues} entity types with mismatched counts")

    return total_issues


def check_storage_usage():
    """Report storage usage."""
    print_header("STORAGE USAGE")

    def get_dir_size(path):
        """Get directory size in bytes."""
        total = 0
        try:
            for entry in os.scandir(path):
                if entry.is_file():
                    total += entry.stat().st_size
                elif entry.is_dir():
                    total += get_dir_size(entry.path)
        except PermissionError:
            pass
        return total

    def format_bytes(bytes_val):
        """Format bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.2f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.2f} PB"

    source_size = get_dir_size(SOURCE_DIR) if SOURCE_DIR.exists() else 0
    parquet_size = get_dir_size(PARQUET_DIR) if PARQUET_DIR.exists() else 0

    print(f"Source data (.gz):     {format_bytes(source_size)}")
    print(f"Parquet data:          {format_bytes(parquet_size)}")
    print(f"Total:                 {format_bytes(source_size + parquet_size)}")

    if parquet_size > 0:
        ratio = source_size / parquet_size
        print(f"Compression ratio:     {ratio:.2f}x")


def main():
    """Main execution."""
    print(f"{BOLD}OpenAlex Data Integrity Checker{NC}")
    print(f"Date: {os.popen('date').read().strip()}")

    # Run checks
    orphans = check_orphan_parquets()
    missing = check_missing_parquets()
    mismatches = check_file_counts()
    check_storage_usage()

    # Final summary
    print_header("SUMMARY")

    total_issues = orphans + mismatches

    if total_issues == 0 and missing == 0:
        print_success("✓ All checks passed! Data is consistent.")
        return 0
    elif orphans > 0:
        print_error(f"✗ Found {orphans} orphan Parquet files - run ETL to cleanup")
        return 1
    elif missing > 0:
        print_warning(f"⚠ Found {missing} source files not yet processed - run ETL")
        return 0
    else:
        print_warning(f"⚠ Found {total_issues} issues - review above")
        return 1


if __name__ == "__main__":
    sys.exit(main())
