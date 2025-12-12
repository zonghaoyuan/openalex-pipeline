# OpenAlex Data Pipeline

Production-grade, incremental data pipeline for analyzing OpenAlex scholarly data on your local server.

## Architecture Overview

```
┌──��──────────────────────────────────────────────────────────────────┐
│                        OpenAlex Data Pipeline                        │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌─────────┐
│  S3 Bucket   │───▶│  Local JSONL │───▶│   Parquet    │───▶│ Metabase│
│ (s3://openalex)│   │ (openalex_data)│  │(openalex_parquet)│  │ +DuckDB │
└──────────────┘    └──────────────┘    └──────────────┘    └─────────┘
      │                    │                    │                  │
   Phase 1             Phase 1              Phase 2           Phase 3
 sync_openalex.sh   (Read-Only SoT)    process_data.py   docker-compose
      │                    │                    │                  │
      └────────────────────┴────────────────────┴──────────────────┘
                              │
                       run_pipeline.sh
                      (Master Orchestrator)
                              │
                         Cron (Weekly)
```

## System Requirements

- **OS**: Linux (Ubuntu/Debian recommended)
- **Storage**: 4TB (1TB for source data, 1TB for Parquet, 2TB buffer)
- **RAM**: 64GB (4GB allocated to Metabase)
- **CPU**: 4+ cores recommended
- **Software**:
  - Python 3.8+
  - AWS CLI
  - Docker & docker-compose
  - DuckDB Python library

## Quick Start

### 1. Install Dependencies

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install AWS CLI
sudo apt-get install awscli -y

# Install Python dependencies
pip3 install duckdb

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install docker-compose
sudo apt-get install docker-compose -y
```

### 2. Initial Setup

```bash
# Clone/navigate to project directory
cd /home/ubuntu

# Make scripts executable (already done if you used the setup)
chmod +x sync_openalex.sh process_data.py run_pipeline.sh setup_metabase.sh

# Setup Metabase (downloads DuckDB plugin and starts container)
./setup_metabase.sh
```

### 3. Run Initial Pipeline

```bash
# Run the complete pipeline for the first time
./run_pipeline.sh
```

This will:
1. Sync data from S3 to `./openalex_data`
2. Convert JSONL.gz files to Parquet in `./openalex_parquet`
3. Generate a summary report

**Note**: Initial run may take several hours depending on data size and network speed.

### 4. Configure Metabase

1. Open http://localhost:3000
2. Create admin account
3. Add Database:
   - Type: DuckDB
   - Name: OpenAlex
   - Database: `:memory:` (recommended) or `/data/openalex.duckdb`
4. In SQL editor, run the contents of `init_duckdb.sql` to create views
5. Start querying!

## File Structure

```
/home/ubuntu/
├── sync_openalex.sh          # Phase 1: S3 sync script
├── process_data.py            # Phase 2: ETL converter with state management
├── run_pipeline.sh            # Phase 4: Master orchestrator
├── setup_metabase.sh          # Metabase setup helper
├── docker-compose.yml         # Metabase service definition
├── init_duckdb.sql            # DuckDB view creation script
├── README.md                  # This file
│
├── openalex_data/             # Source data (READ-ONLY)
│   ├── data/
│   │   ├── authors/
│   │   ├── works/
│   │   └── .../
│   └── legacy-data/           # Excluded from sync
│
├── openalex_parquet/          # Converted Parquet files
│   ├── authors/
│   ├── works/
│   └── .../
│
├── logs/                      # All log files
│   ├── sync_*.log
│   ├── etl_process.log
│   ├── etl_errors.log
│   └── pipeline_*.log
│
├── metabase_plugins/          # DuckDB driver
│   └── duckdb.metabase-driver.jar
│
└── etl_state.db               # SQLite database tracking processed files
```

## Detailed Component Documentation

### Phase 1: S3 Sync (`sync_openalex.sh`)

**Purpose**: Incrementally download new/changed files from S3.

**Features**:
- Uses `aws s3 sync` for efficient delta sync
- Excludes legacy data with `--exclude "*legacy*"`
- No AWS credentials required (public bucket with `--no-sign-request`)
- Comprehensive logging

**Usage**:
```bash
./sync_openalex.sh
```

**Output**: Downloaded files in `./openalex_data/data/`

### Phase 2: ETL Converter (`process_data.py`)

**Purpose**: Convert JSONL.gz to Parquet with incremental processing.

**Key Features**:
- **State Management**: SQLite database tracks processed files by hash
- **Incremental**: Only processes new/modified files
- **Fault Tolerant**: Failed files logged separately, don't block pipeline
- **Schema Evolution**: `union_by_name=true` handles schema changes
- **Compression**: Parquet files use ZSTD compression

**State Database Schema**:
```sql
processed_files (
    file_path TEXT PRIMARY KEY,
    file_hash TEXT,           -- MD5 hash for change detection
    entity_type TEXT,
    processed_at TIMESTAMP,
    record_count INTEGER,
    output_path TEXT
)

failed_files (
    file_path TEXT PRIMARY KEY,
    error_message TEXT,
    failed_at TIMESTAMP,
    retry_count INTEGER
)
```

**Usage**:
```bash
./process_data.py
```

**Manual State Management**:
```bash
# View state database
sqlite3 etl_state.db "SELECT * FROM processed_files LIMIT 10;"

# Check failed files
sqlite3 etl_state.db "SELECT * FROM failed_files;"

# Reset state for specific entity (re-process all)
sqlite3 etl_state.db "DELETE FROM processed_files WHERE entity_type='works';"

# Clear all state (full reprocess)
rm etl_state.db
```

### Phase 3: Serving Layer (Metabase + DuckDB)

**Purpose**: Query Parquet files via Metabase UI.

**Setup**:
```bash
./setup_metabase.sh
```

**DuckDB Views**:
The `init_duckdb.sql` script creates views using wildcard patterns:
```sql
CREATE OR REPLACE VIEW works AS
SELECT * FROM read_parquet('/data/works/**/*.parquet', union_by_name=true);
```

**Benefits**:
- Views automatically include new Parquet files
- No need to restart Metabase when pipeline adds data
- `union_by_name` handles schema evolution

**Example Queries**:
```sql
-- Recent publications
SELECT * FROM works
WHERE publication_year >= 2024
LIMIT 100;

-- Top cited authors
SELECT
    display_name,
    cited_by_count,
    works_count
FROM authors
WHERE cited_by_count > 1000
ORDER BY cited_by_count DESC;

-- Works by institution
SELECT
    w.title,
    w.publication_year,
    w.cited_by_count
FROM works w
WHERE EXISTS (
    SELECT 1 FROM unnest(w.institutions) i
    WHERE i.display_name LIKE '%MIT%'
);
```

### Phase 4: Master Orchestrator (`run_pipeline.sh`)

**Purpose**: Run the complete pipeline with reporting.

**Features**:
- Pre-flight checks (dependencies, permissions)
- Sequential execution: Sync → ETL
- Comprehensive error handling
- Summary report with metrics

**Usage**:
```bash
# Run full pipeline
./run_pipeline.sh

# View help
./run_pipeline.sh --help
```

## Automation with Cron

### Recommended Cron Schedule

```bash
# Edit crontab
crontab -e

# Add one of these schedules:

# Option 1: Weekly (Sunday at 2 AM)
0 2 * * 0 cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1

# Option 2: Bi-weekly (1st and 15th of month at 3 AM)
0 3 1,15 * * cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1

# Option 3: Daily (2 AM)
0 2 * * * cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1

# Option 4: Monthly (1st of month at 4 AM)
0 4 1 * * cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1
```

### Monitoring Cron Jobs

```bash
# View cron log
tail -f ./logs/cron.log

# Check if cron is running
pgrep -a cron

# List active cron jobs
crontab -l

# View system cron logs
grep CRON /var/log/syslog
```

### Email Notifications (Optional)

```bash
# Install mail utilities
sudo apt-get install mailutils -y

# Cron will email you on failures if MAILTO is set
# Add to crontab:
MAILTO=your-email@example.com
0 2 * * 0 cd /home/ubuntu && ./run_pipeline.sh
```

## Operational Guidelines

### Critical Constraints

1. **NEVER modify `./openalex_data`** - This is your Source of Truth
2. **Always check disk space** before running pipeline
3. **Monitor failed files** in `etl_state.db`
4. **Review error logs** in `./logs/etl_errors.log`

### Pre-Run Checklist

```bash
# Check disk space (need at least 100GB free)
df -h .

# Check if pipeline is already running
pgrep -af "run_pipeline.sh"

# Verify Metabase is running (if needed)
docker ps | grep metabase

# Check recent logs for issues
tail -n 50 ./logs/etl_process.log
```

### Post-Run Validation

```bash
# Check pipeline exit status
echo $?  # Should be 0

# Verify new Parquet files
ls -lt ./openalex_parquet/works/ | head

# Query sample data
python3 -c "
import duckdb
con = duckdb.connect(':memory:')
result = con.execute(\"SELECT COUNT(*) FROM read_parquet('./openalex_parquet/works/**/*.parquet')\").fetchone()
print(f'Total works: {result[0]:,}')
"

# Check state database
sqlite3 etl_state.db "
SELECT
    entity_type,
    COUNT(*) as files,
    SUM(record_count) as total_records
FROM processed_files
GROUP BY entity_type;
"
```

## Troubleshooting

### Problem: AWS Sync Fails

```bash
# Check AWS CLI version
aws --version

# Test S3 access
aws s3 ls s3://openalex --no-sign-request

# Re-run sync manually
./sync_openalex.sh
```

### Problem: ETL Conversion Fails

```bash
# Check Python and DuckDB
python3 --version
python3 -c "import duckdb; print(duckdb.__version__)"

# Check error log
cat ./logs/etl_errors.log

# List failed files
sqlite3 etl_state.db "SELECT file_path, error_message FROM failed_files;"

# Retry failed files (delete from failed_files table)
sqlite3 etl_state.db "DELETE FROM failed_files WHERE file_path='<path>';"
```

### Problem: Out of Disk Space

```bash
# Check usage
df -h .

# Find largest directories
du -sh ./openalex_data/* | sort -h
du -sh ./openalex_parquet/* | sort -h

# Clean old logs (keep last 30 days)
find ./logs -name "*.log" -mtime +30 -delete

# Remove legacy data if accidentally downloaded
rm -rf ./openalex_data/legacy-data
```

### Problem: Metabase Can't Connect to DuckDB

```bash
# Check if Metabase is running
docker ps -a | grep metabase

# View Metabase logs
docker-compose logs -f metabase

# Restart Metabase
docker-compose restart metabase

# Verify plugin exists
ls -lh ./metabase_plugins/duckdb.metabase-driver.jar

# Re-download plugin
rm ./metabase_plugins/duckdb.metabase-driver.jar
./setup_metabase.sh
```

### Problem: Pipeline Runs Too Long

```bash
# Check system resources
htop  # or top

# Identify slow files
tail -f ./logs/etl_process.log

# Consider processing specific entities only
# Edit process_data.py CONFIG["entity_types"] to exclude large ones

# Optimize: Use faster disk (SSD) for ./openalex_parquet
```

## Performance Tuning

### ETL Performance

```python
# Edit process_data.py to adjust:

# Increase DuckDB memory limit
duckdb.connect(':memory:', config={'memory_limit': '32GB'})

# Use multiple threads (add to query)
SET threads TO 8;

# Adjust Parquet compression
COMPRESSION ZSTD  # vs SNAPPY, GZIP
```

### Metabase Performance

```yaml
# Edit docker-compose.yml:
environment:
  - MB_JAVA_OPTS=-Xmx8g -Xms2g  # Increase heap size
```

## Data Schema

### Entity Types

| Entity       | Description                     | Typical Size |
|--------------|---------------------------------|--------------|
| works        | Publications, articles, papers  | Largest      |
| authors      | Author profiles                 | Large        |
| institutions | Universities, research orgs     | Medium       |
| sources      | Journals, conferences           | Medium       |
| concepts     | Research topics/keywords        | Medium       |
| topics       | Subject classifications         | Small        |
| funders      | Funding organizations           | Small        |
| publishers   | Publishing companies            | Small        |
| fields       | Academic fields                 | Small        |
| subfields    | Academic subfields              | Small        |
| domains      | High-level domains              | Small        |

### Works Schema (Primary Entity)

Key fields in the `works` table:
- `id`: OpenAlex ID
- `title`: Publication title
- `publication_year`: Year published
- `publication_date`: Full date
- `cited_by_count`: Citation count
- `authorships`: Array of author objects
- `institutions`: Array of affiliated institutions
- `concepts`: Array of associated concepts
- `abstract_inverted_index`: Abstract (inverted index format)
- `doi`, `pmid`, `mag`: External IDs

## Maintenance

### Weekly Tasks

- Monitor cron execution logs
- Check disk space
- Review failed files count

### Monthly Tasks

- Analyze storage usage trends
- Review and archive old logs
- Update Docker images: `docker-compose pull`

### Quarterly Tasks

- Audit data completeness
- Review and optimize queries
- Update DuckDB driver if needed
- Backup `etl_state.db`

## Advanced Usage

### Custom Entity Processing

```python
# Process only specific entities
python3 -c "
import sys
sys.argv = ['process_data.py']
from process_data import CONFIG, main
CONFIG['entity_types'] = ['works', 'authors']  # Only these
main()
"
```

### Querying Without Metabase

```python
import duckdb

con = duckdb.connect(':memory:')

# Query directly from Parquet
result = con.execute("""
    SELECT
        publication_year,
        COUNT(*) as paper_count,
        AVG(cited_by_count) as avg_citations
    FROM read_parquet('./openalex_parquet/works/**/*.parquet')
    WHERE publication_year >= 2020
    GROUP BY publication_year
    ORDER BY publication_year DESC
""").fetchdf()

print(result)
```

### Export to CSV

```bash
duckdb -c "
COPY (
    SELECT * FROM read_parquet('./openalex_parquet/authors/**/*.parquet')
    WHERE cited_by_count > 100
) TO 'top_authors.csv' (HEADER, DELIMITER ',');
"
```

## Security Considerations

- All data from OpenAlex is public (CC0 license)
- No authentication required for S3 sync
- Metabase should be behind firewall or VPN for production
- Consider setting up Metabase authentication
- Regularly update Docker images for security patches

## Support and Resources

- **OpenAlex Documentation**: https://docs.openalex.org
- **DuckDB Documentation**: https://duckdb.org/docs
- **Metabase Documentation**: https://www.metabase.com/docs
- **Issue Tracking**: Check `./logs/etl_errors.log`

## License

This pipeline code is provided as-is. OpenAlex data is licensed under CC0 (public domain).

---

**Version**: 1.0.0
**Last Updated**: 2025-12-12
**Author**: Senior Data Engineer
