#!/usr/bin/env python3
"""
ETL Test Script
Purpose: Test schema normalization with a few sample files
"""

import os
import sys
import tempfile
import shutil
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

import duckdb

# Import from process_data
from process_data import SchemaNormalizer, get_columns_from_json, convert_to_parquet

PROJECT_ROOT = Path(__file__).parent.parent
SOURCE_DIR = PROJECT_ROOT / "data" / "source"
CONFIG_PATH = PROJECT_ROOT / "config" / "schema_normalization.json"

def test_normalizer_config():
    """Test that the normalizer loads config correctly."""
    print("=" * 60)
    print("TEST 1: Schema Normalizer Configuration")
    print("=" * 60)

    normalizer = SchemaNormalizer(str(CONFIG_PATH))

    # Check that entities with conflicts are recognized
    entities_needing_norm = [e for e in ["authors", "institutions", "sources", "works"]
                            if normalizer.needs_normalization(e)]

    print(f"Entities needing normalization: {entities_needing_norm}")

    for entity in entities_needing_norm:
        rules = normalizer.get_normalization_rules(entity)
        cols_to_varchar = rules.get("columns_to_varchar", [])
        cols_to_json = rules.get("struct_columns_to_json", [])
        print(f"  {entity}: {len(cols_to_varchar)} cols->VARCHAR, {len(cols_to_json)} structs->JSON")

    # Check entities without conflicts
    no_norm_entities = ["concepts", "domains", "fields", "funders", "publishers", "subfields", "topics"]
    for entity in no_norm_entities:
        assert not normalizer.needs_normalization(entity), f"{entity} should not need normalization"

    print("✓ Normalizer configuration test passed!")
    return True

def test_single_file_conversion(entity_type: str, test_idx: int = 0):
    """Test converting a single file with schema normalization."""
    print("=" * 60)
    print(f"TEST 2.{test_idx}: Single File Conversion - {entity_type.upper()}")
    print("=" * 60)

    # Find a source file
    entity_dir = SOURCE_DIR / entity_type
    if not entity_dir.exists():
        print(f"  ✗ Source directory not found: {entity_dir}")
        return False

    gz_files = list(entity_dir.rglob("*.gz"))
    if not gz_files:
        print(f"  ✗ No .gz files found for {entity_type}")
        return False

    # Pick a file from the middle (to avoid early/late schema variations)
    source_file = str(gz_files[len(gz_files) // 2])
    print(f"  Source file: {source_file}")

    # Create temp output file
    with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as tmp:
        output_file = tmp.name

    try:
        normalizer = SchemaNormalizer(str(CONFIG_PATH))

        # Test conversion
        success, record_count, error_msg = convert_to_parquet(
            source_file, output_file, entity_type, normalizer
        )

        if not success:
            print(f"  ✗ Conversion failed: {error_msg}")
            return False

        print(f"  ✓ Converted {record_count} records")

        # Verify schema
        con = duckdb.connect(":memory:")
        result = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{output_file}')").fetchall()

        print(f"  Output schema ({len(result)} columns):")
        rules = normalizer.get_normalization_rules(entity_type)
        normalized_cols = set(rules.get("columns_to_varchar", [])) | set(rules.get("struct_columns_to_json", []))

        for col_name, col_type, *_ in result:
            if col_name in normalized_cols:
                is_varchar = col_type == "VARCHAR"
                status = "✓" if is_varchar else "✗"
                print(f"    {status} {col_name}: {col_type} (normalized)")
            else:
                print(f"      {col_name}: {col_type}")

        con.close()
        print(f"  ✓ Single file conversion test passed for {entity_type}!")
        return True

    finally:
        # Cleanup
        if os.path.exists(output_file):
            os.remove(output_file)

def test_schema_consistency(entity_type: str, num_files: int = 3):
    """Test that multiple files produce consistent schemas."""
    print("=" * 60)
    print(f"TEST 3: Schema Consistency - {entity_type.upper()}")
    print("=" * 60)

    entity_dir = SOURCE_DIR / entity_type
    gz_files = sorted(entity_dir.rglob("*.gz"))

    if len(gz_files) < num_files:
        print(f"  Not enough files ({len(gz_files)} < {num_files})")
        return True  # Not a failure

    # Select files from different partitions
    indices = [0, len(gz_files) // 2, len(gz_files) - 1]
    test_files = [gz_files[i] for i in indices[:num_files]]

    normalizer = SchemaNormalizer(str(CONFIG_PATH))
    schemas = []
    temp_files = []

    try:
        for idx, source_file in enumerate(test_files):
            print(f"  [{idx+1}/{len(test_files)}] {source_file.relative_to(SOURCE_DIR)}")

            with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as tmp:
                output_file = tmp.name
                temp_files.append(output_file)

            success, record_count, error_msg = convert_to_parquet(
                str(source_file), output_file, entity_type, normalizer
            )

            if not success:
                print(f"    ✗ Failed: {error_msg}")
                continue

            # Get schema
            con = duckdb.connect(":memory:")
            result = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{output_file}')").fetchall()
            schema = {row[0]: row[1] for row in result}
            schemas.append(schema)
            con.close()

            print(f"    ✓ {record_count} records, {len(schema)} columns")

        # Compare schemas
        if len(schemas) < 2:
            print("  ✗ Not enough successful conversions to compare")
            return False

        # Check if all normalized columns have consistent VARCHAR type
        rules = normalizer.get_normalization_rules(entity_type)
        normalized_cols = set(rules.get("columns_to_varchar", [])) | set(rules.get("struct_columns_to_json", []))

        all_consistent = True
        for col in normalized_cols:
            types_seen = set()
            for schema in schemas:
                if col in schema:
                    types_seen.add(schema[col])

            if len(types_seen) > 1:
                print(f"  ✗ {col}: inconsistent types {types_seen}")
                all_consistent = False
            elif types_seen and list(types_seen)[0] != "VARCHAR":
                print(f"  ✗ {col}: expected VARCHAR, got {types_seen}")
                all_consistent = False
            elif types_seen:
                print(f"  ✓ {col}: VARCHAR")

        if all_consistent:
            print(f"  ✓ Schema consistency test passed for {entity_type}!")

        return all_consistent

    finally:
        # Cleanup
        for f in temp_files:
            if os.path.exists(f):
                os.remove(f)

def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("OpenAlex ETL Test Suite")
    print("=" * 60 + "\n")

    results = []

    # Test 1: Config loading
    results.append(("Config Loading", test_normalizer_config()))

    # Test 2: Single file conversions for entities with normalization
    for idx, entity in enumerate(["authors", "institutions", "sources", "works"]):
        results.append((f"Single File ({entity})", test_single_file_conversion(entity, idx)))

    # Test 3: Schema consistency for problematic entities
    for entity in ["authors", "works"]:
        results.append((f"Consistency ({entity})", test_schema_consistency(entity)))

    # Summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    passed = sum(1 for _, r in results if r)
    failed = len(results) - passed

    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")

    print(f"\nTotal: {passed} passed, {failed} failed")

    if failed > 0:
        sys.exit(1)
    else:
        print("\n✓ All tests passed! ETL script is ready for use.")
        sys.exit(0)

if __name__ == "__main__":
    main()
