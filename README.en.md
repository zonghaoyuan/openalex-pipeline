# OpenAlex Data Pipeline

English | [简体中文](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![DuckDB](https://img.shields.io/badge/DuckDB-1.4.3-orange.svg)](https://duckdb.org/)

Production-grade OpenAlex data pipeline for syncing, transforming, and serving academic data.

## 📋 Table of Contents

- [Features](#features)
- [System Architecture](#system-architecture)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Configuration](#configuration)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## ✨ Features

- **Automatic Sync**: Automatically sync latest academic data from OpenAlex S3
- **Incremental Processing**: Smart incremental ETL based on MD5 hashing, avoiding duplicate processing
- **Data Consistency**: Three-layer protection mechanism ensuring data accuracy (S3 sync + orphan cleanup + query deduplication)
- **Parquet Storage**: Efficient columnar storage format supporting fast queries
- **Metabase Integration**: Out-of-the-box data visualization and analytics platform
- **Email Notifications**: Automatic data update and error reports
- **Automated Execution**: Cron scheduled tasks, no manual intervention required

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenAlex S3 Public Bucket                     │
│                  s3://openalex/data (~1TB)                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ aws s3 sync --delete
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Phase 1: S3 Sync (sync_openalex.sh)           │
│  - Download new files and updates                                │
│  - Delete files not present on remote                            │
│  - Output: data/source/**/*.gz (JSONL.gz format)                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Check file changes
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Phase 2: ETL Transform (process_data.py)            │
│  - MD5 hash change detection                                     │
│  - JSONL.gz → Parquet (ZSTD compression)                        │
│  - Cleanup orphan Parquet files                                  │
│  - SQLite state management                                       │
│  - Output: data/parquet/**/*.parquet                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Generate statistics
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│           Phase 3: Email Notification (send_email_notification.sh) │
│  - Success/failure reports                                       │
│  - Detailed statistics                                           │
│  - Send only when updates detected                               │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│           Phase 4: Data Query (DuckDB + Metabase)               │
│  - DuckDB deduplication views                                    │
│  - Metabase visualization and analytics                          │
│  - RESTful API support                                           │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### System Requirements

- **Operating System**: Linux (Ubuntu 24.04 recommended)
- **Memory**: 64GB RAM
- **Storage**: 2TB+ available space
- **Python**: 3.12+
- **Network**: Stable internet connection

### Installation Steps

1. **Clone Repository**
```bash
cd ~
git clone <repository-url> openalex
cd openalex
```

2. **Install Dependencies**
```bash
# Install Python dependencies
pip3 install --break-system-packages -r config/requirements.txt

# Install AWS CLI (if not already installed)
sudo apt-get update
sudo apt-get install -y awscli

# Install msmtp (email notifications)
sudo apt-get install -y msmtp msmtp-mta mailutils

# Install jq (JSON processing)
sudo apt-get install -y jq
```

3. **Configure Email Notifications**
```bash
# Edit msmtp configuration
nano ~/.msmtprc

# Edit email configuration
nano config/email_config.sh
```

4. **First Run**
```bash
# Run with Screen (recommended)
./run_etl_in_screen.sh

# Or run directly
./run.sh
```

5. **Setup Cron Job**
```bash
# Edit crontab
crontab -e

# Add the following line (runs at 2:00 AM China time daily)
0 18 * * * cd ~/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

## 📖 Usage Guide

### Manual Execution

#### Using Screen (Recommended, prevents SSH disconnection)
```bash
cd ~/openalex

# Start ETL
./run_etl_in_screen.sh

# Attach to session to view progress
screen -r openalex-etl

# Detach from session (ETL continues running)
# Press Ctrl+A, then D

# List all screen sessions
screen -ls
```

#### Direct Execution
```bash
cd ~/openalex
./run.sh
```

### Monitor Progress

#### View Real-time Logs
```bash
# ETL processing logs
tail -f logs/etl_process.log

# Cron execution logs
tail -f logs/cron.log

# Error logs
tail -f logs/etl_errors.log

# Email sending logs
tail -f logs/msmtp.log
```

#### Check Data Integrity
```bash
python3 scripts/check_data_integrity.py
```

#### View Processing Statistics
```bash
# Source file count
find data/source -name "*.gz" | wc -l

# Parquet file count
find data/parquet -name "*.parquet" | wc -l

# Disk usage
du -sh data/source
du -sh data/parquet
```

### Metabase Usage

1. **Start Metabase**
```bash
cd ~/openalex
docker-compose -f config/docker-compose.yml up -d
```

2. **Access Interface**
- URL: `http://localhost:3000`
- First access requires admin account setup

3. **Configure Data Source**
- Database type: DuckDB
- Database file: `/data/parquet` (container path)
- Run SQL: Execute view creation statements from `config/init_duckdb.sql`

4. **Query Examples**
```sql
-- Query papers published in 2024
SELECT * FROM works WHERE publication_year = 2024 LIMIT 100;

-- Query highly cited authors
SELECT * FROM authors WHERE cited_by_count > 1000 ORDER BY cited_by_count DESC;

-- Count papers by institution
SELECT institution_id, COUNT(*) as paper_count
FROM works
GROUP BY institution_id
ORDER BY paper_count DESC
LIMIT 20;
```

## ⚙️ Configuration

### Directory Structure

```
~/openalex/
├── run.sh                          # Quick start script
├── run_etl_in_screen.sh            # Screen startup script
├── README.md                       # Project documentation
├── RUN_INSTRUCTIONS.md             # Run instructions
├── VERIFICATION_REPORT.md          # Verification report
│
├── scripts/                        # Scripts directory
│   ├── sync_openalex.sh            # S3 sync script
│   ├── process_data.py             # ETL transform script
│   ├── run_pipeline.sh             # Main pipeline script
│   ├── send_email_notification.sh  # Email notification script
│   ├── check_data_integrity.py     # Data integrity check
│   └── setup_metabase.sh           # Metabase setup script
│
├── config/                         # Configuration directory
│   ├── requirements.txt            # Python dependencies
│   ├── init_duckdb.sql             # DuckDB view definitions
│   ├── docker-compose.yml          # Metabase configuration
│   └── email_config.sh             # Email configuration
│
├── data/                           # Data directory (not in Git)
│   ├── source/                     # OpenAlex source data (JSONL.gz)
│   │   ├── authors/
│   │   ├── works/
│   │   └── ...
│   └── parquet/                    # Transformed Parquet files
│       ├── authors/
│       ├── works/
│       └── ...
│
├── state/                          # State management (not in Git)
│   └── etl_state.db                # SQLite state database
│
├── logs/                           # Logs directory (not in Git)
│   ├── etl_process.log             # ETL processing logs
│   ├── etl_errors.log              # Error logs
│   ├── cron.log                    # Cron execution logs
│   ├── msmtp.log                   # Email sending logs
│   ├── sync_stats.json             # Sync statistics
│   ├── etl_stats.json              # ETL statistics
│   └── combined_stats.json         # Combined statistics
│
└── metabase/                       # Metabase data (not in Git)
    └── plugins/                    # Metabase plugins
```

### Key Configuration Files

#### 1. Python Dependencies (`config/requirements.txt`)
```txt
duckdb>=1.4.3
pandas>=2.3.3
pyarrow>=22.0.0
numpy>=2.3.5
```

#### 2. Email Configuration (`config/email_config.sh`)
```bash
RECIPIENT_EMAIL="your-email@example.com"
SENDER_EMAIL="pipeline@example.com"
NOTIFY_ON_UPDATE=true
NOTIFY_ON_FAILURE=true
```

#### 3. SMTP Configuration (`~/.msmtprc`)
```
account openalex
host smtp.example.com
port 587
user pipeline@example.com
password YOUR_PASSWORD
from pipeline@example.com
```

## 🔧 Monitoring & Maintenance

### Automated Monitoring

The system automatically notifies important events via email:

- ✅ **Successful Update**: File changes detected and successfully processed
- ⚠️ **Failure Report**: ETL processing failed
- 🔕 **No Update**: Silent (no email sent)

### Periodic Checks

Recommended to run data integrity checks weekly:

```bash
# Check data integrity
python3 scripts/check_data_integrity.py

# Check disk space
df -h ~/openalex

# Check Cron status
crontab -l
sudo systemctl status cron
```

### Log Rotation

Recommended to setup log rotation to prevent log files from becoming too large:

```bash
# Clean logs older than 30 days
find logs -name "*.log" -mtime +30 -delete
```

### Performance Optimization

If processing is slow, consider:

1. **Increase memory limit** (edit `process_data.py`):
```python
duckdb.connect(':memory:', config={'memory_limit': '32GB'})
```

2. **Use SSD storage** for data directory

3. **Optimize network connection** to speed up S3 sync

## 🐛 Troubleshooting

### Common Issues

#### 1. ETL Processing Failed

**Symptom**: Error messages in logs

**Solution**:
```bash
# View error logs
tail -50 logs/etl_errors.log

# Check failed records in state database
sqlite3 state/etl_state.db "SELECT * FROM failed_files;"

# Manually retry
./run.sh
```

#### 2. Insufficient Disk Space

**Symptom**: "No space left on device" error

**Solution**:
```bash
# Check disk usage
df -h

# Clean old logs
find logs -name "*.log" -mtime +7 -delete

# If necessary, delete source files (can be re-synced)
rm -rf data/source/*
./run.sh
```

#### 3. Cron Job Not Executing

**Symptom**: Not running at expected time

**Solution**:
```bash
# Check cron service
sudo systemctl status cron

# View system logs
sudo tail -f /var/log/syslog | grep CRON

# Manually test cron command
cd ~/openalex && ./run.sh
```

#### 4. Email Sending Failed

**Symptom**: msmtp.log shows errors

**Solution**:
```bash
# Check msmtp configuration
cat ~/.msmtprc

# Test email sending
echo "Test" | mail -s "Test Subject" your-email@example.com

# View logs
tail -20 logs/msmtp.log
```

#### 5. Data Duplication

**Symptom**: Queries return duplicate records

**Solution**:
```bash
# Run data integrity check
python3 scripts/check_data_integrity.py

# If orphan files found, manually run ETL cleanup
python3 scripts/process_data.py

# Verify DuckDB views include deduplication logic
# Check config/init_duckdb.sql
```

## 🔐 Security Recommendations

1. **Protect configuration files**:
```bash
chmod 600 ~/.msmtprc
chmod 600 config/email_config.sh
```

2. **Use environment variables** to store sensitive information (optional)

3. **Regularly backup state database**:
```bash
cp state/etl_state.db state/etl_state.db.backup
```

4. **Restrict file permissions**:
```bash
chmod 700 ~/openalex
```

## 📊 Data Description

### OpenAlex Entity Types

| Entity | Description | Typical File Count |
|------|------|-----------|
| works | Academic works (papers, books, etc.) | ~1,700 |
| authors | Authors | ~300 |
| institutions | Institutions | ~8 |
| sources | Journals, conferences, etc. | ~40 |
| concepts | Subject concepts | ~3 |
| publishers | Publishers | ~1 |
| funders | Funding organizations | ~1 |
| topics | Topics | ~1 |
| domains | Domains | ~1 |
| fields | Fields | ~1 |
| subfields | Subfields | ~1 |

### Data Update Frequency

- **OpenAlex Updates**: Approximately every 30-45 days
- **Our Sync**: Daily checks
- **Actual Processing**: Only when changes detected

### Data Volume Estimates

- **Source Data (JSONL.gz)**: ~1TB
- **Parquet Data**: ~800GB (compressed)
- **Total File Count**: 2,078+ files

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 Changelog

### v1.0.0 (2025-12-12)

**Features**:
- ✨ Initial release
- ✨ S3 automatic sync (with --delete support)
- ✨ Incremental ETL processing
- ✨ Automatic orphan Parquet cleanup
- ✨ DuckDB query deduplication
- ✨ Email notification system
- ✨ Metabase integration
- ✨ Data integrity check tool

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

## 👥 Author

- **[Zonghao Yuan](https://yzh.im)** - Project Development & Maintenance

## 🙏 Acknowledgments

- [OpenAlex](https://openalex.org/) - Providing open academic data
- [DuckDB](https://duckdb.org/) - Powerful analytical database
- [Metabase](https://www.metabase.com/) - Excellent data visualization tool

## 📞 Support

For questions or suggestions, please:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review [RUN_INSTRUCTIONS.md](RUN_INSTRUCTIONS.md) for detailed guide
3. Submit an Issue

---

**⚠️ Important Notice**: This system processes large-scale data, please ensure:
- Sufficient disk space (2TB+)
- Stable network connection
- Adequate system resources (64GB RAM)
- Regular monitoring and maintenance

**🚀 Get Started Now**: `cd ~/openalex && ./run_etl_in_screen.sh`
