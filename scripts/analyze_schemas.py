#!/usr/bin/env python3
"""
Schema Analysis Script - Fixed Version
Purpose: Analyze all entity schemas to detect type conflicts
"""

import duckdb
import json
import sys
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple

PROJECT_ROOT = Path(__file__).parent.parent
SOURCE_DIR = PROJECT_ROOT / "data" / "source"
PARQUET_DIR = PROJECT_ROOT / "data" / "parquet"

ENTITY_TYPES = [
    "authors", "concepts", "domains", "fields", "funders",
    "institutions", "publishers", "sources", "subfields", "topics", "works"
]

def get_schema_from_parquet(file_path: str) -> Dict[str, str]:
    """Extract schema from a Parquet file using DESCRIBE."""
    try:
        con = duckdb.connect(":memory:")
        query = f"DESCRIBE SELECT * FROM read_parquet('{file_path}')"
        result = con.execute(query).fetchall()
        con.close()

        schema = {}
        for row in result:
            col_name = row[0]
            col_type = row[1]
            schema[col_name] = col_type

        return schema
    except Exception as e:
        return {"_error": str(e)}

def get_schema_from_json(file_path: str) -> Dict[str, str]:
    """Extract schema from a JSON.gz file using DESCRIBE."""
    try:
        con = duckdb.connect(":memory:")
        query = f"""
            DESCRIBE SELECT * FROM read_json_auto(
                '{file_path}',
                maximum_object_size=100000000,
                ignore_errors=true,
                sample_size=100
            )
        """
        result = con.execute(query).fetchall()
        con.close()

        schema = {}
        for row in result:
            col_name = row[0]
            col_type = row[1]
            schema[col_name] = col_type

        return schema
    except Exception as e:
        return {"_error": str(e)}

def analyze_parquet_schemas(entity_type: str) -> Dict:
    """Analyze schemas from existing Parquet files."""
    entity_dir = PARQUET_DIR / entity_type

    if not entity_dir.exists():
        return {"error": f"Parquet directory not found: {entity_dir}"}

    parquet_files = sorted(entity_dir.rglob("*.parquet"))

    if not parquet_files:
        return {"error": "No parquet files found"}

    print(f"\n{'='*80}")
    print(f"Analyzing PARQUET: {entity_type.upper()}")
    print(f"{'='*80}")
    print(f"Total files: {len(parquet_files)}")

    # Sample files
    max_files = 30
    if len(parquet_files) > max_files:
        step = len(parquet_files) // max_files
        sampled_files = [parquet_files[i] for i in range(0, len(parquet_files), step)][:max_files]
    else:
        sampled_files = parquet_files

    print(f"Sampling {len(sampled_files)} files...")

    # Track column types
    column_types = defaultdict(set)
    column_type_files = defaultdict(lambda: defaultdict(list))  # col -> type -> files
    valid_schemas = 0

    for idx, file_path in enumerate(sampled_files, 1):
        rel_path = str(file_path.relative_to(PARQUET_DIR))
        print(f"  [{idx}/{len(sampled_files)}] {rel_path}", end="")

        schema = get_schema_from_parquet(str(file_path))

        if "_error" in schema:
            print(f" ✗ {schema['_error'][:50]}")
            continue

        print(f" ✓ ({len(schema)} cols)")
        valid_schemas += 1

        for col_name, col_type in schema.items():
            column_types[col_name].add(col_type)
            column_type_files[col_name][col_type].append(rel_path)

    # Identify conflicts
    conflicts = {}
    for col_name, types in column_types.items():
        if len(types) > 1:
            conflicts[col_name] = {
                "types": sorted(list(types)),
                "examples": {t: column_type_files[col_name][t][:2] for t in types}
            }

    result = {
        "source": "parquet",
        "total_files": len(parquet_files),
        "analyzed_files": valid_schemas,
        "total_columns": len(column_types),
        "columns_with_conflicts": len(conflicts),
        "conflicts": conflicts,
        "all_columns": {col: list(types) for col, types in sorted(column_types.items())}
    }

    # Print summary
    print(f"\nSummary:")
    print(f"  Analyzed: {valid_schemas}/{len(sampled_files)} files")
    print(f"  Total columns: {len(column_types)}")
    print(f"  Columns with conflicts: {len(conflicts)}")

    if conflicts:
        print(f"\nType Conflicts:")
        for col_name, info in sorted(conflicts.items()):
            print(f"  - {col_name}:")
            for t in info["types"]:
                examples = info["examples"][t]
                print(f"      {t}")
                for ex in examples[:1]:
                    print(f"        └─ {ex}")

    return result

def main():
    """Main analysis function."""
    print("="*80)
    print("OpenAlex Schema Analysis (from Parquet files)")
    print("="*80)

    all_results = {}

    # Analyze all entities from existing Parquet files
    for entity in ENTITY_TYPES:
        all_results[entity] = analyze_parquet_schemas(entity)

    # Save results
    output_file = PROJECT_ROOT / "logs" / "schema_analysis.json"
    output_file.parent.mkdir(exist_ok=True)

    with open(output_file, 'w') as f:
        json.dump(all_results, f, indent=2)

    # Overall summary
    print(f"\n{'='*80}")
    print(f"OVERALL SUMMARY")
    print(f"{'='*80}")

    entities_with_conflicts = []
    entities_without_conflicts = []

    for entity, result in all_results.items():
        if "error" in result:
            print(f"  ⚠ {entity}: {result['error']}")
            continue

        if result["columns_with_conflicts"] > 0:
            entities_with_conflicts.append((entity, result["columns_with_conflicts"]))
        else:
            entities_without_conflicts.append(entity)

    print(f"\n✓ Entities WITHOUT type conflicts ({len(entities_without_conflicts)}):")
    for entity in entities_without_conflicts:
        print(f"    {entity}")

    print(f"\n⚠ Entities WITH type conflicts ({len(entities_with_conflicts)}):")
    for entity, count in entities_with_conflicts:
        print(f"    {entity}: {count} columns")

    print(f"\nDetailed results saved to: {output_file}")

if __name__ == "__main__":
    main()
