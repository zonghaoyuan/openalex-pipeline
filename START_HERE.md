# OpenAlex 数据管道 - 开始使用

欢迎使用重新组织后的 OpenAlex 数据管道系统！

## 快速启动（3步）

```bash
# 1. 进入项目目录
cd /home/ubuntu/openalex

# 2. 验证安装
./scripts/validate_pipeline.sh

# 3. 运行管道
./run.sh
```

## 目录说明

| 目录 | 用途 | 说明 |
|------|------|------|
| `scripts/` | 所有可执行脚本 | 6个核心脚本 |
| `config/` | 配置文件 | docker-compose, SQL, requirements |
| `data/source/` | 原始数据 | S3 同步的 JSONL.gz 文件（只读） |
| `data/parquet/` | 转换数据 | ETL 处理后的 Parquet 文件 |
| `state/` | 状态数据库 | 追踪已处理文件 |
| `logs/` | 日志文件 | 所有运行日志 |
| `metabase/` | Metabase | 插件和数据 |
| `docs/` | 文档 | README, 快速指南等 |

## 常用命令

### 运行完整管道
```bash
cd /home/ubuntu/openalex
./run.sh
```

### 单独运行各阶段
```bash
# S3 同步
./scripts/sync_openalex.sh

# ETL 转换
./scripts/process_data.py

# 设置 Metabase
./scripts/setup_metabase.sh

# 验证系统
./scripts/validate_pipeline.sh
```

### 查看状态
```bash
# 查看已处理文件
sqlite3 state/etl_state.db "SELECT entity_type, COUNT(*) FROM processed_files GROUP BY entity_type;"

# 查看失败文件
sqlite3 state/etl_state.db "SELECT * FROM failed_files;"

# 查看日志
tail -f logs/etl_process.log
```

## Cron 自动化

编辑 crontab：
```bash
crontab -e
```

添加每周执行任务（周日凌晨2点）：
```
0 2 * * 0 cd /home/ubuntu/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

## 重要变更（相比旧版本）

### S3 同步
- **旧**: 同步整个 `s3://openalex` 到 `./openalex_data`
- **新**: 只同步 `s3://openalex/data` 到 `data/source/`
- **优势**: 只下载数据，不包含元数据文件

### 路径
所有路径都已更新为新的结构：
```
旧: ./openalex_data/data        → 新: data/source/
旧: ./openalex_parquet          → 新: data/parquet/
旧: ./etl_state.db              → 新: state/etl_state.db
旧: ./logs                      → 新: logs/
```

## 数据完整性

✅ **验证通过**
- 原始文件数: 2,078 个 .gz 文件
- 新位置文件数: 2,078 个 .gz 文件
- 实体类型: 11 个（全部迁移）

## Metabase 访问

1. 启动 Metabase：
   ```bash
   cd /home/ubuntu/openalex
   ./scripts/setup_metabase.sh
   ```

2. 访问: http://localhost:3000

3. 配置 DuckDB 连接：
   - Database: `:memory:` 或 `/data/openalex.duckdb`
   - 运行 `config/init_duckdb.sql` 创建视图

## 文档参考

- `docs/README.md` - 完整文档
- `docs/QUICKSTART.md` - 快速参考
- `docs/SYSTEM_OVERVIEW.txt` - 系统概览
- `MIGRATION_COMPLETE.md` - 迁移报告

## 故障排除

### 问题：脚本无法执行
```bash
chmod +x run.sh
chmod +x scripts/*.sh scripts/*.py
```

### 问题：路径错误
所有脚本使用相对路径，确保从项目根目录运行：
```bash
cd /home/ubuntu/openalex
./run.sh
```

### 问题：Metabase 无法连接
```bash
# 检查 Docker
docker ps -a | grep metabase

# 重启
cd config
docker-compose restart
```

### 问题：数据不见了
数据已迁移到新位置，检查：
```bash
ls -lh data/source/
find data/source -name "*.gz" | wc -l
```

## 获取帮助

```bash
# 查看管道脚本帮助
./scripts/run_pipeline.sh --help

# 运行验证
./scripts/validate_pipeline.sh
```

---

**准备就绪！开始使用吧！** 🚀

```bash
cd /home/ubuntu/openalex && ./run.sh
```
