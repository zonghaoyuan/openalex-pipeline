#!/usr/bin/env python3
"""
OpenAlex Smart ETL Converter
Purpose: Incrementally convert JSONL.gz files to Parquet format with state tracking
         and schema normalization to ensure consistent types across all partitions
Author: Senior Data Engineer
Date: 2025-12-12
Updated: 2025-12-13 - Added schema normalization support
"""

import os
import sys
import sqlite3
import hashlib
import logging
import json
import glob
from pathlib import Path
from datetime import datetime, timezone
from typing import List, Dict, Tuple, Optional
import duckdb

###############################################################################
# Configuration
###############################################################################

# Get project root directory (parent of scripts/)
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent

CONFIG = {
    "source_dir": str(PROJECT_ROOT / "data" / "source"),
    "target_dir": str(PROJECT_ROOT / "data" / "parquet"),
    "state_db": str(PROJECT_ROOT / "state" / "etl_state.db"),
    "error_log": str(PROJECT_ROOT / "logs" / "etl_errors.log"),
    "process_log": str(PROJECT_ROOT / "logs" / "etl_process.log"),
    "schema_config": str(PROJECT_ROOT / "config" / "schema_normalization.json"),
    "entity_types": [
        "authors",
        "concepts",
        "domains",
        "fields",
        "funders",
        "institutions",
        "publishers",
        "sources",
        "subfields",
        "topics",
        "works",
    ],
}

###############################################################################
# Logging Setup
###############################################################################

# Create logs directory
os.makedirs(PROJECT_ROOT / "logs", exist_ok=True)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(CONFIG["process_log"]),
        logging.StreamHandler(sys.stdout),
    ],
)

logger = logging.getLogger(__name__)

###############################################################################
# Schema Normalization
###############################################################################


class SchemaNormalizer:
    """Handles schema normalization based on configuration."""

    def __init__(self, config_path: str):
        self.config_path = config_path
        self.rules = {}
        self._load_config()

    def _load_config(self):
        """Load schema normalization configuration."""
        if os.path.exists(self.config_path):
            with open(self.config_path, "r") as f:
                self.rules = json.load(f)
            logger.info(f"Loaded schema normalization config from {self.config_path}")
        else:
            logger.warning(f"Schema config not found at {self.config_path}, using defaults")
            self.rules = {}

    def get_normalization_rules(self, entity_type: str) -> Dict:
        """Get normalization rules for an entity type."""
        return self.rules.get(entity_type, {
            "columns_to_varchar": [],
            "struct_columns_to_json": []
        })

    def needs_normalization(self, entity_type: str) -> bool:
        """Check if an entity type needs schema normalization."""
        rules = self.get_normalization_rules(entity_type)
        return bool(rules.get("columns_to_varchar") or rules.get("struct_columns_to_json"))

    def build_select_clause(self, entity_type: str, columns: List[str]) -> str:
        """
        Build SELECT clause with CAST expressions for normalization.

        Args:
            entity_type: The entity type (e.g., 'works', 'authors')
            columns: List of column names from the source file

        Returns:
            SELECT clause string
        """
        rules = self.get_normalization_rules(entity_type)
        cols_to_varchar = set(rules.get("columns_to_varchar", []))
        cols_to_json = set(rules.get("struct_columns_to_json", []))

        select_parts = []
        for col in columns:
            # Escape column names that might be reserved words
            escaped_col = f'"{col}"' if col in ['type', 'year', 'source', 'domain', 'version'] else col

            if col in cols_to_varchar:
                # Convert to VARCHAR (JSON string)
                select_parts.append(f'CAST({escaped_col} AS VARCHAR) AS "{col}"')
            elif col in cols_to_json:
                # Convert struct to JSON string
                select_parts.append(f'to_json({escaped_col})::VARCHAR AS "{col}"')
            else:
                # Keep as-is
                select_parts.append(f'{escaped_col} AS "{col}"')

        return ", ".join(select_parts)


###############################################################################
# State Management
###############################################################################


class StateManager:
    """Manages ETL state using SQLite to track processed files."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_database()

    def _init_database(self):
        """Initialize the state database with necessary tables."""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS processed_files (
                    file_path TEXT PRIMARY KEY,
                    file_hash TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    file_size INTEGER,
                    record_count INTEGER,
                    output_path TEXT
                )
            """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS failed_files (
                    file_path TEXT PRIMARY KEY,
                    entity_type TEXT NOT NULL,
                    error_message TEXT,
                    failed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    retry_count INTEGER DEFAULT 0
                )
            """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_entity_type
                ON processed_files(entity_type)
            """
            )
            conn.commit()
        logger.info(f"State database initialized at {self.db_path}")

    def is_processed(self, file_path: str, file_hash: str) -> bool:
        """Check if a file has already been processed with the same hash."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute(
                """
                SELECT file_hash FROM processed_files
                WHERE file_path = ?
            """,
                (file_path,),
            )
            result = cursor.fetchone()
            if result:
                return result[0] == file_hash
            return False

    def mark_processed(
        self,
        file_path: str,
        file_hash: str,
        entity_type: str,
        file_size: int,
        record_count: int,
        output_path: str,
    ):
        """Mark a file as successfully processed."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO processed_files
                (file_path, file_hash, entity_type, file_size, record_count, output_path, processed_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """,
                (file_path, file_hash, entity_type, file_size, record_count, output_path),
            )
            # Remove from failed files if it was there
            conn.execute("DELETE FROM failed_files WHERE file_path = ?", (file_path,))
            conn.commit()

    def mark_failed(self, file_path: str, entity_type: str, error_message: str):
        """Mark a file as failed with error details."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO failed_files
                (file_path, entity_type, error_message, failed_at, retry_count)
                VALUES (
                    ?, ?, ?, CURRENT_TIMESTAMP,
                    COALESCE((SELECT retry_count FROM failed_files WHERE file_path = ?), 0) + 1
                )
            """,
                (file_path, entity_type, error_message, file_path),
            )
            conn.commit()

    def get_stats(self) -> Dict:
        """Get processing statistics."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute(
                """
                SELECT
                    entity_type,
                    COUNT(*) as file_count,
                    SUM(record_count) as total_records,
                    SUM(file_size) as total_size
                FROM processed_files
                GROUP BY entity_type
            """
            )
            processed_stats = {}
            for row in cursor.fetchall():
                processed_stats[row[0]] = {
                    "files": row[1],
                    "records": row[2] or 0,
                    "size_bytes": row[3] or 0,
                }

            cursor = conn.execute(
                """
                SELECT entity_type, COUNT(*) as error_count
                FROM failed_files
                GROUP BY entity_type
            """
            )
            failed_stats = {row[0]: row[1] for row in cursor.fetchall()}

        return {"processed": processed_stats, "failed": failed_stats}

    def clear_entity(self, entity_type: str):
        """Clear all records for a specific entity type."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM processed_files WHERE entity_type = ?", (entity_type,))
            conn.execute("DELETE FROM failed_files WHERE entity_type = ?", (entity_type,))
            conn.commit()
        logger.info(f"Cleared state for entity: {entity_type}")


###############################################################################
# File Processing
###############################################################################


def compute_file_hash(file_path: str) -> str:
    """Compute MD5 hash of a file for change detection."""
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def discover_files(source_dir: str, entity_types: List[str]) -> Dict[str, List[str]]:
    """Discover all .gz files organized by entity type."""
    files_by_entity = {entity: [] for entity in entity_types}

    for entity in entity_types:
        entity_path = Path(source_dir) / entity
        if entity_path.exists():
            gz_files = list(entity_path.rglob("*.gz"))
            files_by_entity[entity] = [str(f) for f in gz_files]
            logger.info(f"Found {len(gz_files)} files for entity: {entity}")

    return files_by_entity


def get_columns_from_json(con: duckdb.DuckDBPyConnection, source_file: str) -> List[str]:
    """Get column names from a JSON file."""
    try:
        query = f"""
            DESCRIBE SELECT * FROM read_json_auto(
                '{source_file}',
                maximum_object_size=100000000,
                ignore_errors=true,
                sample_size=100
            )
        """
        result = con.execute(query).fetchall()
        return [row[0] for row in result]
    except Exception as e:
        logger.warning(f"Could not get columns from {source_file}: {e}")
        return []


def convert_to_parquet(
    source_file: str,
    output_file: str,
    entity_type: str,
    normalizer: SchemaNormalizer
) -> Tuple[bool, int, str]:
    """
    Convert a JSONL.gz file to Parquet using DuckDB with schema normalization.

    Returns: (success, record_count, error_message)
    """
    try:
        # Create output directory
        os.makedirs(os.path.dirname(output_file), exist_ok=True)

        # Initialize DuckDB connection
        con = duckdb.connect(":memory:")

        # Check if normalization is needed
        if normalizer.needs_normalization(entity_type):
            # Get columns from the source file
            columns = get_columns_from_json(con, source_file)

            if not columns:
                # Fallback: read without normalization if column detection fails
                logger.warning(f"Column detection failed for {source_file}, using default conversion")
                query = f"""
                    COPY (
                        SELECT * FROM read_json_auto(
                            '{source_file}',
                            maximum_object_size=100000000,
                            ignore_errors=true,
                            union_by_name=true
                        )
                    ) TO '{output_file}' (FORMAT PARQUET, COMPRESSION ZSTD);
                """
            else:
                # Build normalized SELECT clause
                select_clause = normalizer.build_select_clause(entity_type, columns)

                query = f"""
                    COPY (
                        SELECT {select_clause}
                        FROM read_json_auto(
                            '{source_file}',
                            maximum_object_size=100000000,
                            ignore_errors=true,
                            union_by_name=true
                        )
                    ) TO '{output_file}' (FORMAT PARQUET, COMPRESSION ZSTD);
                """
        else:
            # No normalization needed - use simple conversion
            query = f"""
                COPY (
                    SELECT * FROM read_json_auto(
                        '{source_file}',
                        maximum_object_size=100000000,
                        ignore_errors=false,
                        union_by_name=true
                    )
                ) TO '{output_file}' (FORMAT PARQUET, COMPRESSION ZSTD);
            """

        con.execute(query)

        # Get record count
        count_query = f"""
            SELECT COUNT(*) FROM read_parquet('{output_file}')
        """
        record_count = con.execute(count_query).fetchone()[0]

        con.close()

        logger.info(
            f"Successfully converted {entity_type}: {source_file} "
            f"({record_count} records) -> {output_file}"
        )

        return True, record_count, ""

    except Exception as e:
        error_msg = f"Failed to convert {source_file}: {str(e)}"
        logger.error(error_msg)

        # Log to error file
        os.makedirs(os.path.dirname(CONFIG["error_log"]), exist_ok=True)
        with open(CONFIG["error_log"], "a") as f:
            f.write(f"{datetime.now().isoformat()} | {error_msg}\n")

        return False, 0, str(e)


def cleanup_orphan_parquets(
    source_dir: str, target_dir: str, entity_types: List[str]
) -> Dict:
    """
    Remove Parquet files whose corresponding source .gz files no longer exist.

    This handles the case where OpenAlex deletes files from S3 (e.g., when
    entities move to new partitions and old partition files are removed).
    """
    stats = {
        "scanned": 0,
        "removed": 0,
        "kept": 0,
        "errors": 0,
    }

    logger.info("\n" + "=" * 80)
    logger.info("CLEANUP: Scanning for orphan Parquet files")
    logger.info("=" * 80)

    for entity_type in entity_types:
        # Find all Parquet files for this entity
        parquet_pattern = f"{target_dir}/{entity_type}/**/*.parquet"
        parquet_files = glob.glob(parquet_pattern, recursive=True)

        if not parquet_files:
            continue

        logger.info(f"\nChecking {entity_type}: {len(parquet_files)} Parquet files")

        for parquet_file in parquet_files:
            stats["scanned"] += 1

            try:
                # Derive the corresponding source file path
                # Example transformation:
                # /path/to/data/parquet/authors/updated_date=2025-10-01/part_000.parquet
                # -> /path/to/data/source/authors/updated_date=2025-10-01/part_000.gz

                # Get relative path from target_dir
                rel_path = os.path.relpath(parquet_file, target_dir)

                # Replace .parquet with .gz
                source_rel_path = rel_path.replace(".parquet", ".gz")

                # Construct full source path
                source_file = os.path.join(source_dir, source_rel_path)

                # Check if source file exists
                if os.path.exists(source_file):
                    stats["kept"] += 1
                else:
                    # Source file doesn't exist - this is an orphan
                    logger.info(f"  Removing orphan: {rel_path}")
                    logger.info(f"    (source not found: {source_rel_path})")

                    os.remove(parquet_file)
                    stats["removed"] += 1

            except Exception as e:
                logger.error(f"  Error processing {parquet_file}: {e}")
                stats["errors"] += 1

    logger.info("\n" + "-" * 80)
    logger.info("CLEANUP SUMMARY:")
    logger.info(f"  Parquet files scanned:  {stats['scanned']}")
    logger.info(f"  Orphans removed:        {stats['removed']}")
    logger.info(f"  Valid files kept:       {stats['kept']}")
    logger.info(f"  Errors:                 {stats['errors']}")
    logger.info("=" * 80)

    return stats


def process_entity(
    entity_type: str,
    files: List[str],
    state_mgr: StateManager,
    normalizer: SchemaNormalizer
) -> Dict:
    """Process all files for a specific entity type."""
    stats = {
        "total": len(files),
        "new": 0,
        "skipped": 0,
        "processed": 0,
        "failed": 0,
    }

    needs_norm = normalizer.needs_normalization(entity_type)
    norm_status = "WITH schema normalization" if needs_norm else "no normalization needed"

    logger.info(f"\n{'='*60}")
    logger.info(f"Processing entity: {entity_type.upper()} ({norm_status})")
    logger.info(f"{'='*60}")

    for idx, source_file in enumerate(files, 1):
        # Compute file hash for change detection
        file_hash = compute_file_hash(source_file)
        file_size = os.path.getsize(source_file)

        # Check if already processed
        if state_mgr.is_processed(source_file, file_hash):
            logger.debug(f"[{idx}/{len(files)}] Skipping (already processed): {source_file}")
            stats["skipped"] += 1
            continue

        stats["new"] += 1

        # Determine output path
        # Convert: data/works/updated_date=2025-10-16/part_0000.gz
        # To: openalex_parquet/works/updated_date=2025-10-16/part_0000.parquet
        rel_path = Path(source_file).relative_to(CONFIG["source_dir"])
        output_file = str(Path(CONFIG["target_dir"]) / rel_path).replace(".gz", ".parquet")

        logger.info(f"[{idx}/{len(files)}] Processing: {source_file}")

        # Convert to Parquet
        success, record_count, error_msg = convert_to_parquet(
            source_file, output_file, entity_type, normalizer
        )

        if success:
            state_mgr.mark_processed(
                source_file, file_hash, entity_type, file_size, record_count, output_file
            )
            stats["processed"] += 1
        else:
            state_mgr.mark_failed(source_file, entity_type, error_msg)
            stats["failed"] += 1

    return stats


###############################################################################
# Main Execution
###############################################################################


def main():
    """Main ETL execution function."""
    logger.info("=" * 80)
    logger.info("OpenAlex Smart ETL Converter - Starting")
    logger.info("=" * 80)

    start_time = datetime.now()

    # Initialize state manager and schema normalizer
    os.makedirs(os.path.dirname(CONFIG["state_db"]), exist_ok=True)
    state_mgr = StateManager(CONFIG["state_db"])
    normalizer = SchemaNormalizer(CONFIG["schema_config"])

    # Log normalization status
    logger.info("\nSchema Normalization Status:")
    for entity in CONFIG["entity_types"]:
        if normalizer.needs_normalization(entity):
            rules = normalizer.get_normalization_rules(entity)
            num_cols = len(rules.get("columns_to_varchar", [])) + len(rules.get("struct_columns_to_json", []))
            logger.info(f"  {entity}: {num_cols} columns will be normalized to VARCHAR")
        else:
            logger.info(f"  {entity}: no normalization needed")

    # Discover files
    logger.info(f"\nScanning source directory: {CONFIG['source_dir']}")
    files_by_entity = discover_files(CONFIG["source_dir"], CONFIG["entity_types"])

    total_files = sum(len(files) for files in files_by_entity.values())
    logger.info(f"\nTotal files discovered: {total_files}")

    # Process each entity type
    overall_stats = {
        "total_files": total_files,
        "new_files": 0,
        "processed": 0,
        "skipped": 0,
        "failed": 0,
    }

    for entity_type, files in files_by_entity.items():
        if not files:
            logger.info(f"Skipping {entity_type}: No files found")
            continue

        entity_stats = process_entity(entity_type, files, state_mgr, normalizer)

        overall_stats["new_files"] += entity_stats["new"]
        overall_stats["processed"] += entity_stats["processed"]
        overall_stats["skipped"] += entity_stats["skipped"]
        overall_stats["failed"] += entity_stats["failed"]

    # Cleanup orphan Parquet files (files whose source .gz no longer exists)
    cleanup_stats = cleanup_orphan_parquets(
        CONFIG["source_dir"], CONFIG["target_dir"], CONFIG["entity_types"]
    )

    # Print final summary
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    logger.info("\n" + "=" * 80)
    logger.info("ETL SUMMARY")
    logger.info("=" * 80)
    logger.info(f"Total files discovered:  {overall_stats['total_files']}")
    logger.info(f"New files (unprocessed): {overall_stats['new_files']}")
    logger.info(f"Successfully processed:  {overall_stats['processed']}")
    logger.info(f"Skipped (cached):        {overall_stats['skipped']}")
    logger.info(f"Failed:                  {overall_stats['failed']}")
    logger.info(f"\nDuration: {duration:.2f} seconds")

    # Get cumulative statistics
    cumulative_stats = state_mgr.get_stats()
    logger.info("\nCUMULATIVE STATISTICS (All-Time):")
    logger.info("-" * 80)

    for entity, stats in cumulative_stats["processed"].items():
        size_gb = stats["size_bytes"] / (1024**3)
        logger.info(
            f"{entity:15s} | Files: {stats['files']:5d} | "
            f"Records: {stats['records']:12,d} | Size: {size_gb:8.2f} GB"
        )

    if cumulative_stats["failed"]:
        logger.warning("\nFAILED FILES BY ENTITY:")
        for entity, count in cumulative_stats["failed"].items():
            logger.warning(f"  {entity}: {count} files")

    logger.info("=" * 80)

    # Write statistics to JSON file for email notification
    stats_output = {
        "success": overall_stats["failed"] == 0,
        "files_processed": overall_stats["processed"],
        "files_skipped": overall_stats["skipped"],
        "files_failed": overall_stats["failed"],
        "duration_seconds": int(duration),
        "records_added": sum(stats["records"] for stats in cumulative_stats["processed"].values()),
        "orphans_removed": cleanup_stats["removed"],
        "orphans_scanned": cleanup_stats["scanned"],
        "entity_stats": {
            entity: {
                "files": stats["files"],
                "records": stats["records"]
            }
            for entity, stats in cumulative_stats["processed"].items()
        },
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

    # Write to JSON file
    stats_file = os.path.join(PROJECT_ROOT, "logs", "etl_stats.json")
    with open(stats_file, "w") as f:
        json.dump(stats_output, f, indent=2)

    # Exit with appropriate code
    if overall_stats["failed"] > 0:
        logger.warning(
            f"\nWARNING: {overall_stats['failed']} files failed. "
            f"Check {CONFIG['error_log']} for details."
        )
        sys.exit(1)
    else:
        logger.info("\nETL completed successfully!")
        sys.exit(0)


if __name__ == "__main__":
    main()
