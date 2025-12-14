# OpenAlex Data Pipeline

English | [简体中文](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![DuckDB](https://img.shields.io/badge/DuckDB-1.1.3-orange.svg)](https://duckdb.org/)

Production-grade OpenAlex data pipeline with automatic sync, incremental ETL, and visualization.

## Features

- **Auto Sync**: Automatically sync latest scholarly data from OpenAlex S3
- **Incremental Processing**: Smart incremental ETL based on MD5 hashing
- **Schema Normalization**: Automatically handles cross-partition type conflicts
- **Metabase Integration**: Out-of-the-box data visualization platform
- **Email Notifications**: Automatic data update reports

## Data Scale

| Entity | Records | Description |
|--------|---------|-------------|
| works | 463M | Academic papers |
| authors | 116M | Authors |
| sources | 255K | Journals/Conferences |
| institutions | 102K | Institutions |
| concepts | 65K | Academic concepts |
| funders | 32K | Funding agencies |
| topics | 4,516 | Topics |

## System Requirements

- **OS**: Linux (Ubuntu 24.04 recommended)
- **RAM**: 64GB
- **Storage**: 2TB+ available space
- **Docker**: Installed and running

## Quick Start

### 1. Clone Repository

```bash
cd ~
git clone https://github.com/zonghaoyuan/openalex-pipeline.git openalex
cd openalex
```

### 2. Install Dependencies

```bash
# Python dependencies
pip3 install duckdb

# System tools
sudo apt-get update
sudo apt-get install -y awscli jq
```

### 3. Run Data Pipeline

```bash
# Run with Screen (recommended to prevent SSH disconnection)
./run_etl_in_screen.sh

# Check progress
screen -r openalex-etl

# Detach session (Ctrl+A, D)
```

First run takes a long time:
- S3 Sync: ~12 hours (downloading ~1TB data)
- ETL Conversion: ~12 hours (processing 2000+ files)

### 4. Start Metabase

```bash
cd config
sudo docker compose up -d
```

Access `http://SERVER_IP:3000`

### 5. Configure Database Connection

Add database in Metabase:
- **Type**: DuckDB
- **Database file**: `/duckdb/openalex.duckdb`

## Directory Structure

```
openalex/
├── run.sh                      # Quick start script
├── run_etl_in_screen.sh        # Screen launch script
├── scripts/
│   ├── sync_openalex.sh        # S3 sync
│   ├── process_data.py         # ETL conversion (with schema normalization)
│   ├── run_pipeline.sh         # Main pipeline
│   └── send_email_notification.sh
├── config/
│   ├── docker-compose.yml      # Metabase container config
│   ├── Dockerfile.metabase     # Custom image (with DuckDB driver)
│   ├── create_views.sql        # DuckDB view definitions
│   ├── schema_normalization.json # Schema normalization rules
│   └── email_config.sh         # Email configuration
├── data/                       # Data directory (not in Git)
│   ├── source/                 # OpenAlex source data (JSONL.gz)
│   └── parquet/                # Converted Parquet files
├── state/                      # ETL state database
└── logs/                       # Log directory
```

## Scheduled Tasks

```bash
# Edit crontab
crontab -e

# Check for updates daily at 2:00 AM (China time, UTC 18:00)
0 18 * * * cd ~/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

## Common Commands

```bash
# View ETL logs
tail -f logs/etl_process.log

# View data statistics
python3 -c "
import duckdb
con = duckdb.connect('data/openalex.duckdb', read_only=True)
for table in ['works', 'authors', 'sources', 'institutions']:
    count = con.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
    print(f'{table}: {count:,}')
"

# Restart Metabase
cd config && sudo docker compose restart
```

## Metabase Query Examples

```sql
-- Count papers by year
SELECT publication_year, COUNT(*) as count
FROM works
WHERE publication_year >= 2020
GROUP BY publication_year
ORDER BY publication_year DESC;

-- Query papers by a specific author
SELECT w.title, w.publication_year, w.cited_by_count
FROM works w
WHERE w.authorships LIKE '%Albert Einstein%'
ORDER BY w.cited_by_count DESC
LIMIT 100;
```

## Troubleshooting

### ETL Processing Failed

```bash
# View error logs
tail -50 logs/etl_errors.log

# View failed files
sqlite3 state/etl_state.db "SELECT * FROM failed_files;"

# Re-run
./run.sh
```

### Metabase Connection Issues

```bash
# Check container status
sudo docker ps

# View container logs
sudo docker logs openalex-metabase

# Rebuild container
cd config
sudo docker compose down
sudo docker compose up -d --build
```

## Technical Architecture

```
OpenAlex S3 ──────▶ JSONL.gz ──────▶ Parquet ──────▶ DuckDB ──────▶ Metabase
                      │                 │               │
               sync_openalex.sh   process_data.py   create_views.sql
                      │                 │               │
                      └─────── Schema Normalization ───┘
```

**Schema Normalization**: The ETL process automatically converts type-conflicting columns to VARCHAR, ensuring cross-partition query compatibility.

## License

MIT License

## Author

- **[Zonghao Yuan](https://yzh.im)**

## Acknowledgments

- [OpenAlex](https://openalex.org/) - Open scholarly data
- [DuckDB](https://duckdb.org/) - Analytical database
- [Metabase](https://www.metabase.com/) - Data visualization
