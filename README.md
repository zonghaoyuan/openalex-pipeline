# OpenAlex 数据管道

[English](README.en.md) | 简体中文

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![DuckDB](https://img.shields.io/badge/DuckDB-1.1.3-orange.svg)](https://duckdb.org/)

生产级 OpenAlex 数据管道，支持自动同步、增量转换和可视化分析。

## 功能特性

- **自动同步**: 从 OpenAlex S3 自动同步最新学术数据
- **增量处理**: 基于 MD5 哈希的智能增量 ETL
- **Schema 规范化**: 自动处理跨分区的类型差异
- **Metabase 集成**: 开箱即用的数据可视化平台
- **邮件通知**: 自动发送数据更新报告

## 数据规模

| 实体 | 记录数 | 说明 |
|------|--------|------|
| works | 4.63亿 | 学术论文 |
| authors | 1.16亿 | 作者 |
| sources | 25.5万 | 期刊/会议 |
| institutions | 10.2万 | 机构 |
| concepts | 6.5万 | 学科概念 |
| funders | 3.2万 | 资助机构 |
| topics | 4,516 | 主题 |

## 系统要求

- **操作系统**: Linux (Ubuntu 24.04 推荐)
- **内存**: 64GB RAM
- **存储**: 2TB+ 可用空间
- **Docker**: 已安装并运行

## 快速开始

### 1. 克隆仓库

```bash
cd ~
git clone https://github.com/zonghaoyuan/openalex-pipeline.git openalex
cd openalex
```

### 2. 安装依赖

```bash
# Python 依赖
pip3 install duckdb

# 系统工具
sudo apt-get update
sudo apt-get install -y awscli jq
```

### 3. 运行数据管道

```bash
# 使用 Screen 运行（推荐，避免 SSH 断开）
./run_etl_in_screen.sh

# 查看进度
screen -r openalex-etl

# 分离会话（Ctrl+A, D）
```

首次运行需要较长时间：
- S3 同步: ~12小时（下载 ~1TB 数据）
- ETL 转换: ~12小时（处理 2000+ 文件）

### 4. 启动 Metabase

```bash
cd config
sudo docker compose up -d
```

访问 `http://服务器IP:3000`

### 5. 配置数据库连接

在 Metabase 中添加数据库：
- **类型**: DuckDB
- **数据库文件**: `/duckdb/openalex.duckdb`

## 目录结构

```
openalex/
├── run.sh                      # 快速启动脚本
├── run_etl_in_screen.sh        # Screen 启动脚本
├── scripts/
│   ├── sync_openalex.sh        # S3 同步
│   ├── process_data.py         # ETL 转换（含 Schema 规范化）
│   ├── run_pipeline.sh         # 主管道
│   └── send_email_notification.sh
├── config/
│   ├── docker-compose.yml      # Metabase 容器配置
│   ├── Dockerfile.metabase     # 自定义镜像（含 DuckDB 驱动）
│   ├── create_views.sql        # DuckDB 视图定义
│   ├── schema_normalization.json # Schema 规范化规则
│   └── email_config.sh         # 邮件配置
├── data/                       # 数据目录（不纳入 Git）
│   ├── source/                 # OpenAlex 源数据 (JSONL.gz)
│   └── parquet/                # 转换后的 Parquet 文件
├── state/                      # ETL 状态数据库
└── logs/                       # 日志目录
```

## 定时任务

```bash
# 编辑 crontab
crontab -e

# 每天凌晨 2:00（中国时间，即 UTC 18:00）检查更新
0 18 * * * cd ~/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

## 常用命令

```bash
# 查看 ETL 日志
tail -f logs/etl_process.log

# 查看数据统计
python3 -c "
import duckdb
con = duckdb.connect('data/openalex.duckdb', read_only=True)
for table in ['works', 'authors', 'sources', 'institutions']:
    count = con.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
    print(f'{table}: {count:,}')
"

# 重启 Metabase
cd config && sudo docker compose restart
```

## Metabase 查询示例

```sql
-- 按年份统计论文数量
SELECT publication_year, COUNT(*) as count
FROM works
WHERE publication_year >= 2020
GROUP BY publication_year
ORDER BY publication_year DESC;

-- 查询特定作者的论文
SELECT w.title, w.publication_year, w.cited_by_count
FROM works w
WHERE w.authorships LIKE '%Albert Einstein%'
ORDER BY w.cited_by_count DESC
LIMIT 100;
```

## 故障排除

### ETL 处理失败

```bash
# 查看错误日志
tail -50 logs/etl_errors.log

# 查看失败文件
sqlite3 state/etl_state.db "SELECT * FROM failed_files;"

# 重新运行
./run.sh
```

### Metabase 无法连接

```bash
# 检查容器状态
sudo docker ps

# 查看容器日志
sudo docker logs openalex-metabase

# 重建容器
cd config
sudo docker compose down
sudo docker compose up -d --build
```

## 技术架构

```
OpenAlex S3 ──────▶ JSONL.gz ──────▶ Parquet ──────▶ DuckDB ──────▶ Metabase
                      │                 │               │
               sync_openalex.sh   process_data.py   create_views.sql
                      │                 │               │
                      └─────── Schema 规范化 ──────────┘
```

**Schema 规范化**: ETL 过程自动将类型冲突的列转换为 VARCHAR，确保跨分区查询的兼容性。

## 许可证

MIT License

## 作者

- **[Zonghao Yuan](https://yzh.im)**

## 致谢

- [OpenAlex](https://openalex.org/) - 开放学术数据
- [DuckDB](https://duckdb.org/) - 分析数据库
- [Metabase](https://www.metabase.com/) - 数据可视化
