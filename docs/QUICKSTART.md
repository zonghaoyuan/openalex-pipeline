# OpenAlex Pipeline - Quick Start Guide

## Installation (5 minutes)

```bash
# 1. Install all dependencies
./install_dependencies.sh

# 2. Setup Metabase
./setup_metabase.sh

# 3. Run initial pipeline (may take hours)
./run_pipeline.sh
```

## Daily Operations

### Run Pipeline Manually
```bash
./run_pipeline.sh
```

### Check Status
```bash
# View latest logs
tail -f ./logs/etl_process.log

# Check Parquet file count
find ./openalex_parquet -name "*.parquet" | wc -l

# View state database
sqlite3 etl_state.db "SELECT entity_type, COUNT(*) FROM processed_files GROUP BY entity_type;"
```

### Access Metabase
```bash
# Start Metabase (if not running)
docker-compose up -d

# Access at: http://localhost:3000
# Default connection: DuckDB at :memory:
# Run init_duckdb.sql to create views
```

## Automation Setup

### Add to Cron (Weekly on Sundays at 2 AM)

```bash
crontab -e

# Add this line:
0 2 * * 0 cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1
```

### Monitor Cron Jobs

```bash
# View cron log
tail -f ./logs/cron.log

# List cron jobs
crontab -l
```

## Common Tasks

### Query Data Locally (Without Metabase)

```python
import duckdb
con = duckdb.connect(':memory:')

# Query works
df = con.execute("""
    SELECT publication_year, COUNT(*) as count
    FROM read_parquet('./openalex_parquet/works/**/*.parquet')
    GROUP BY publication_year
    ORDER BY publication_year DESC
    LIMIT 10
""").fetchdf()

print(df)
```

### Check Failed Files

```bash
sqlite3 etl_state.db "SELECT * FROM failed_files;"
```

### Reset State (Force Full Reprocess)

```bash
# Backup first!
cp etl_state.db etl_state.db.backup

# Remove state
rm etl_state.db

# Re-run pipeline
./run_pipeline.sh
```

### View Disk Usage

```bash
du -sh ./openalex_data ./openalex_parquet
df -h .
```

## Troubleshooting

### Pipeline Fails
```bash
# Check error log
cat ./logs/etl_errors.log

# Check process log
tail -100 ./logs/etl_process.log
```

### Out of Space
```bash
# Clean old logs
find ./logs -name "*.log" -mtime +30 -delete

# Remove legacy data if accidentally downloaded
rm -rf ./openalex_data/legacy-data
```

### Metabase Won't Start
```bash
# Check Docker
docker ps -a | grep metabase

# View logs
docker-compose logs -f metabase

# Restart
docker-compose restart metabase
```

## File Reference

| File | Purpose |
|------|---------|
| `run_pipeline.sh` | **Main script** - Run this for full pipeline |
| `sync_openalex.sh` | S3 sync (Phase 1) |
| `process_data.py` | ETL converter (Phase 2) |
| `docker-compose.yml` | Metabase service |
| `init_duckdb.sql` | DuckDB views for Metabase |
| `setup_metabase.sh` | One-time Metabase setup |
| `install_dependencies.sh` | One-time dependency installation |
| `etl_state.db` | State tracking database |
| `README.md` | Full documentation |

## Architecture

```
S3 → sync_openalex.sh → ./openalex_data (Source of Truth)
                              ↓
                      process_data.py (ETL)
                              ↓
                      ./openalex_parquet
                              ↓
                      Metabase + DuckDB
```

## Key Features

- ✓ **Incremental**: Only processes new/changed files
- ✓ **Fault-Tolerant**: Failed files logged, don't block pipeline
- ✓ **Stateful**: Tracks processed files in SQLite
- ✓ **Read-Only Source**: Never modifies original data
- ✓ **Auto-Discovery**: New Parquet files automatically visible in Metabase
- ✓ **Schema Evolution**: Handles minor schema changes gracefully

## Support

See `README.md` for detailed documentation.
Check `./logs/` directory for all logs.
