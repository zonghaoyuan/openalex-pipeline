# OpenAlex 数据管道

[English](README.en.md) | 简体中文

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![DuckDB](https://img.shields.io/badge/DuckDB-1.4.3-orange.svg)](https://duckdb.org/)

生产级 OpenAlex 数据管道，用于同步、转换和提供学术数据服务。

## 📋 目录

- [功能特性](#-功能特性)
- [系统架构](#-系统架构)
- [快速开始](#-快速开始)
- [使用指南](#-使用指南)
- [配置说明](#-配置说明)
- [监控与维护](#-监控与维护)
- [故障排除](#-故障排除)
- [贡献指南](#-贡献指南)

## ✨ 功能特性

- **自动同步**: 从 OpenAlex S3 自动同步最新学术数据
- **增量处理**: 基于 MD5 哈希的智能增量 ETL，避免重复处理
- **数据一致性**: 三层防护机制确保数据准确性（S3 同步 + 孤儿清理 + 查询去重）
- **Parquet 存储**: 高效的列式存储格式，支持快速查询
- **Metabase 集成**: 开箱即用的数据可视化和分析平台
- **邮件通知**: 自动发送数据更新和错误报告
- **自动化运行**: Cron 定时任务，无需人工干预

## 🏗️ 系统架构

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
│  - 下载新文件和更新                                               │
│  - 删除远程不存在的文件                                            │
│  - 输出: data/source/**/*.gz (JSONL.gz 格式)                     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ 检查文件变化
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Phase 2: ETL 转换 (process_data.py)                 │
│  - MD5 哈希检测变化                                               │
│  - JSONL.gz → Parquet (ZSTD 压缩)                               │
│  - 清理孤儿 Parquet 文件                                          │
│  - SQLite 状态管理                                                │
│  - 输出: data/parquet/**/*.parquet                               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ 生成统计
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│           Phase 3: 邮件通知 (send_email_notification.sh)         │
│  - 成功/失败报告                                                  │
│  - 详细统计信息                                                   │
│  - 仅在有更新时发送                                                │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│           Phase 4: 数据查询 (DuckDB + Metabase)                  │
│  - DuckDB 去重视图                                                │
│  - Metabase 可视化分析                                            │
│  - RESTful API 支持                                              │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 系统要求

- **操作系统**: Linux (Ubuntu 24.04 推荐)
- **内存**: 64GB RAM
- **存储**: 2TB+ 可用空间
- **Python**: 3.12+
- **网络**: 稳定的互联网连接

### 安装步骤

1. **克隆仓库**
```bash
cd ~
git clone <repository-url> openalex
cd openalex
```

2. **安装依赖**
```bash
# 安装 Python 依赖
pip3 install --break-system-packages -r config/requirements.txt

# 安装 AWS CLI（如果未安装）
sudo apt-get update
sudo apt-get install -y awscli

# 安装 msmtp（邮件通知）
sudo apt-get install -y msmtp msmtp-mta mailutils

# 安装 jq（JSON 处理）
sudo apt-get install -y jq
```

3. **配置邮件通知**
```bash
# 编辑 msmtp 配置
nano ~/.msmtprc

# 编辑邮件配置
nano config/email_config.sh
```

4. **首次运行**
```bash
# 使用 Screen 运行（推荐）
./run_etl_in_screen.sh

# 或直接运行
./run.sh
```

5. **设置定时任务**
```bash
# 编辑 crontab
crontab -e

# 添加以下行（每天凌晨 2:00 中国时间）
0 18 * * * cd ~/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

## 📖 使用指南

### 手动运行

#### 使用 Screen（推荐，避免 SSH 断开）
```bash
cd ~/openalex

# 启动 ETL
./run_etl_in_screen.sh

# 连接到会话查看进度
screen -r openalex-etl

# 分离会话（ETL 继续运行）
# 按 Ctrl+A，然后按 D

# 查看所有 screen 会话
screen -ls
```

#### 直接运行
```bash
cd ~/openalex
./run.sh
```

### 监控进度

#### 查看实时日志
```bash
# ETL 处理日志
tail -f logs/etl_process.log

# Cron 执行日志
tail -f logs/cron.log

# 错误日志
tail -f logs/etl_errors.log

# 邮件发送日志
tail -f logs/msmtp.log
```

#### 检查数据一致性
```bash
python3 scripts/check_data_integrity.py
```

#### 查看处理统计
```bash
# 源文件数量
find data/source -name "*.gz" | wc -l

# Parquet 文件数量
find data/parquet -name "*.parquet" | wc -l

# 磁盘使用
du -sh data/source
du -sh data/parquet
```

### Metabase 使用

1. **启动 Metabase**
```bash
cd ~/openalex
sudo docker compose -f config/docker-compose.yml up -d
```

2. **访问界面**
- 直接访问: `http://SERVER_IP:3000`
- 通过反向代理: 配置1Panel等，后端 `http://localhost:3000`

3. **配置数据源**
- 数据库类型: **DuckDB**
- 数据库文件: `/duckdb/openalex.duckdb`

4. **重要提示**
⚠️ 不要直接点击大表（works、authors），会超时！请使用SQL查询。

5. **推荐查询示例**
```sql
-- 查询小表（测试连接）
SELECT * FROM read_parquet('/data/domains/**/*.parquet');

-- 按年份统计论文（优化版）
SELECT
    publication_year,
    COUNT(*) as paper_count
FROM read_parquet('/data/works/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true,
                   columns=['id', 'publication_year'])
WHERE publication_year >= 2020
GROUP BY publication_year
ORDER BY publication_year DESC;
```

6. **详细文档**
- 📖 [METABASE_SETUP.md](METABASE_SETUP.md) - 完整使用指南
- 📋 [docs/CONFIGURATION_CHECKLIST.md](docs/CONFIGURATION_CHECKLIST.md) - 配置清单

## ⚙️ 配置说明

### 目录结构

```
~/openalex/
├── run.sh                          # 快速启动脚本
├── run_etl_in_screen.sh            # Screen 启动脚本
├── README.md                       # 项目文档
├── RUN_INSTRUCTIONS.md             # 运行指南
├── VERIFICATION_REPORT.md          # 验证报告
│
├── scripts/                        # 脚本目录
│   ├── sync_openalex.sh            # S3 同步脚本
│   ├── process_data.py             # ETL 转换脚本
│   ├── run_pipeline.sh             # 主管道脚本
│   ├── send_email_notification.sh  # 邮件通知脚本
│   ├── check_data_integrity.py     # 数据一致性检查
│   └── setup_metabase.sh           # Metabase 设置脚本
│
├── config/                         # 配置目录
│   ├── requirements.txt            # Python 依赖
│   ├── init_duckdb.sql             # DuckDB 视图定义
│   ├── docker-compose.yml          # Metabase 配置
│   └── email_config.sh             # 邮件配置
│
├── data/                           # 数据目录（不纳入 Git）
│   ├── source/                     # OpenAlex 源数据 (JSONL.gz)
│   │   ├── authors/
│   │   ├── works/
│   │   └── ...
│   └── parquet/                    # 转换后的 Parquet 文件
│       ├── authors/
│       ├── works/
│       └── ...
│
├── state/                          # 状态管理（不纳入 Git）
│   └── etl_state.db                # SQLite 状态数据库
│
├── logs/                           # 日志目录（不纳入 Git）
│   ├── etl_process.log             # ETL 处理日志
│   ├── etl_errors.log              # 错误日志
│   ├── cron.log                    # Cron 执行日志
│   ├── msmtp.log                   # 邮件发送日志
│   ├── sync_stats.json             # 同步统计
│   ├── etl_stats.json              # ETL 统计
│   └── combined_stats.json         # 合并统计
│
└── metabase/                       # Metabase 数据（不纳入 Git）
    └── plugins/                    # Metabase 插件
```

### 关键配置文件

#### 1. Python 依赖 (`config/requirements.txt`)
```txt
duckdb>=1.4.3
pandas>=2.3.3
pyarrow>=22.0.0
numpy>=2.3.5
```

#### 2. 邮件配置 (`config/email_config.sh`)
```bash
RECIPIENT_EMAIL="your-email@example.com"
SENDER_EMAIL="pipeline@example.com"
NOTIFY_ON_UPDATE=true
NOTIFY_ON_FAILURE=true
```

#### 3. SMTP 配置 (`~/.msmtprc`)
```
account openalex
host smtp.example.com
port 587
user pipeline@example.com
password YOUR_PASSWORD
from pipeline@example.com
```

## 🔧 监控与维护

### 自动化监控

系统通过邮件自动通知重要事件：

- ✅ **成功更新**: 检测到文件变化并成功处理
- ⚠️ **失败报告**: ETL 处理失败
- 🔕 **无更新**: 静默（不发送邮件）

### 定期检查

建议每周运行一次数据一致性检查：

```bash
# 检查数据完整性
python3 scripts/check_data_integrity.py

# 检查磁盘空间
df -h ~/openalex

# 检查 Cron 状态
crontab -l
sudo systemctl status cron
```

### 日志轮转

建议设置日志轮转以避免日志文件过大：

```bash
# 清理 30 天前的日志
find logs -name "*.log" -mtime +30 -delete
```

### 性能优化

如果处理速度慢，可以考虑：

1. **增加内存限制**（编辑 `process_data.py`）:
```python
duckdb.connect(':memory:', config={'memory_limit': '32GB'})
```

2. **使用 SSD 存储**数据目录

3. **优化网络连接**以加快 S3 同步

## 🐛 故障排除

### 常见问题

#### 1. ETL 处理失败

**症状**: 日志中出现错误信息

**解决方案**:
```bash
# 查看错误日志
tail -50 logs/etl_errors.log

# 查看状态数据库中的失败记录
sqlite3 state/etl_state.db "SELECT * FROM failed_files;"

# 手动重试
./run.sh
```

#### 2. 磁盘空间不足

**症状**: "No space left on device" 错误

**解决方案**:
```bash
# 检查磁盘使用
df -h

# 清理旧日志
find logs -name "*.log" -mtime +7 -delete

# 如果必要，删除源文件（可以重新同步）
rm -rf data/source/*
./run.sh
```

#### 3. Cron 任务未执行

**症状**: 预期时间没有运行

**解决方案**:
```bash
# 检查 cron 服务
sudo systemctl status cron

# 查看系统日志
sudo tail -f /var/log/syslog | grep CRON

# 手动测试 cron 命令
cd ~/openalex && ./run.sh
```

#### 4. 邮件发送失败

**症状**: msmtp.log 显示错误

**解决方案**:
```bash
# 检查 msmtp 配置
cat ~/.msmtprc

# 测试邮件发送
echo "Test" | mail -s "Test Subject" your-email@example.com

# 查看日志
tail -20 logs/msmtp.log
```

#### 5. 数据重复

**症状**: 查询返回重复记录

**解决方案**:
```bash
# 运行数据一致性检查
python3 scripts/check_data_integrity.py

# 如果发现孤儿文件，手动运行 ETL 清理
python3 scripts/process_data.py

# 验证 DuckDB 视图包含去重逻辑
# 检查 config/init_duckdb.sql
```

## 🔐 安全建议

1. **保护配置文件**:
```bash
chmod 600 ~/.msmtprc
chmod 600 config/email_config.sh
```

2. **使用环境变量**存储敏感信息（可选）

3. **定期备份状态数据库**:
```bash
cp state/etl_state.db state/etl_state.db.backup
```

4. **限制文件权限**:
```bash
chmod 700 ~/openalex
```

## 📊 数据说明

### OpenAlex 实体类型

| 实体 | 说明 | 典型文件数 |
|------|------|-----------|
| works | 学术作品（论文、书籍等） | ~1,700 |
| authors | 作者 | ~300 |
| institutions | 机构 | ~8 |
| sources | 期刊、会议等 | ~40 |
| concepts | 学科概念 | ~3 |
| publishers | 出版商 | ~1 |
| funders | 资助机构 | ~1 |
| topics | 主题 | ~1 |
| domains | 领域 | ~1 |
| fields | 学科 | ~1 |
| subfields | 子学科 | ~1 |

### 数据更新频率

- **OpenAlex 更新**: 约每 30-45 天一次
- **我们的同步**: 每天检查一次
- **实际处理**: 仅在检测到变化时

### 数据量估算

- **源数据 (JSONL.gz)**: ~1TB
- **Parquet 数据**: ~800GB (压缩后)
- **总文件数**: 2,078+ 个

## 🤝 贡献指南

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📝 变更日志

### v1.0.0 (2025-12-12)

**功能**:
- ✨ 初始版本发布
- ✨ S3 自动同步（支持 --delete）
- ✨ 增量 ETL 处理
- ✨ 孤儿 Parquet 自动清理
- ✨ DuckDB 查询去重
- ✨ 邮件通知系统
- ✨ Metabase 集成
- ✨ 数据一致性检查工具

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 👥 作者

- **[Zonghao Yuan](https://yzh.im)** - 项目开发与维护

## 🙏 致谢

- [OpenAlex](https://openalex.org/) - 提供开放的学术数据
- [DuckDB](https://duckdb.org/) - 强大的分析数据库
- [Metabase](https://www.metabase.com/) - 优秀的数据可视化工具

## 📞 支持

如有问题或建议，请：
1. 查看 [故障排除](#故障排除) 部分
2. 查看 [RUN_INSTRUCTIONS.md](RUN_INSTRUCTIONS.md) 详细指南
3. 提交 Issue

---

**⚠️ 重要提示**: 本系统处理大规模数据，请确保：
- 充足的磁盘空间（2TB+）
- 稳定的网络连接
- 足够的系统资源（64GB RAM）
- 定期监控和维护

**🚀 现在开始**: `cd ~/openalex && ./run_etl_in_screen.sh`
