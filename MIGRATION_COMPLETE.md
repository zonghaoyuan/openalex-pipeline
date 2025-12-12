# OpenAlex 目录迁移完成报告

**迁移时间**: 2025-12-12
**状态**: ✅ 成功完成

## 迁移概要

所有 OpenAlex 相关的文件和数据已成功迁移到 `/home/ubuntu/openalex/` 目录下，采用更清晰的组织结构。

## 新目录结构

```
/home/ubuntu/openalex/
├── run.sh                          ← 快捷启动脚本
│
├── scripts/                        ← 所有可执行脚本 (6个)
│   ├── sync_openalex.sh
│   ├── process_data.py
│   ├── run_pipeline.sh
│   ├── setup_metabase.sh
│   ├── install_dependencies.sh
│   └── validate_pipeline.sh
│
├── config/                         ← 配置文件 (3个)
│   ├── docker-compose.yml
│   ├── init_duckdb.sql
│   └── requirements.txt
│
├── data/                           ← 数据目录
│   ├── source/                     ← 原始数据 (READ-ONLY)
│   │   ├── authors/                │ 2,078 个 .gz 文件
│   │   ├── works/                  │ 总计约 1TB
│   │   └── ... (11个实体类型)      │
│   │
│   └── parquet/                    ← 转换后的 Parquet 文件
│       └── (待 ETL 处理)           │
│
├── state/                          ← 状态数据库
│   └── (etl_state.db 将在首次运行时创建)
│
├── logs/                           ← 日志文件
│   └── (运行时自动创建)
│
├── metabase/                       ← Metabase 相关
│   └── plugins/
│       └── (DuckDB 驱动待安装)
│
└── docs/                           ← 文档 (4个)
    ├── README.md
    ├── QUICKSTART.md
    ├── SYSTEM_OVERVIEW.txt
    └── PROPOSED_DIRECTORY_STRUCTURE.txt
```

## 已完成的更新

### 1. 脚本路径更新
所有脚本已更新为使用新的相对路径：

- ✅ `sync_openalex.sh`: S3 同步目标改为 `data/source/`，且只同步 `s3://openalex/data`
- ✅ `process_data.py`: 源目录、目标目录、状态数据库、日志路径全部更新
- ✅ `run_pipeline.sh`: 所有脚本引用和数据路径更新
- ✅ `setup_metabase.sh`: 插件目录和数据路径更新
- ✅ `install_dependencies.sh`: requirements.txt 路径更新
- ✅ `validate_pipeline.sh`: 所有验证路径更新

### 2. 配置文件更新
- ✅ `docker-compose.yml`: Volume 挂载路径更新为 `../data/parquet` 和 `../metabase/plugins`

### 3. 数据迁移
- ✅ 2,078 个 .gz 文件成功从 `openalex_data/data/` 迁移到 `openalex/data/source/`
- ✅ 11 个实体类型目录完整保留

### 4. 清理工作
- ✅ 删除旧的 `openalex_data/` 目录
- ✅ 移动旧的参考文档到 `docs/` 目录

## 重要变更

### S3 同步策略更新
根据您的建议，`sync_openalex.sh` 现在：
- **旧行为**: 同步 `s3://openalex` → `./openalex_data`
- **新行为**: 同步 `s3://openalex/data` → `openalex/data/source`

**优势**:
- 只同步实际数据，不下载 S3 根目录的元数据文件
- `data/source/` 更纯粹，只包含 11 个实体类型的数据
- 更符合"数据源"的语义

## 快速开始使用

### 方式 1: 使用快捷脚本（推荐）
```bash
cd /home/ubuntu/openalex
./run.sh
```

### 方式 2: 直接调用主脚本
```bash
cd /home/ubuntu/openalex
./scripts/run_pipeline.sh
```

### 验证安装
```bash
cd /home/ubuntu/openalex
./scripts/validate_pipeline.sh
```

## Cron 任务更新

如果您之前已设置 cron 任务，请更新为新路径：

### 旧的 crontab
```bash
0 2 * * 0 cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1
```

### 新的 crontab
```bash
0 2 * * 0 cd /home/ubuntu/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

或者：
```bash
0 2 * * 0 cd /home/ubuntu/openalex && ./scripts/run_pipeline.sh >> ./logs/cron.log 2>&1
```

## 数据完整性验证

✅ **数据迁移验证**:
- 原始位置: `openalex_data/data/` 有 2,078 个 .gz 文件
- 新位置: `openalex/data/source/` 有 2,078 个 .gz 文件
- **状态**: 100% 完整

✅ **实体类型验证**:
所有 11 个实体类型完整迁移:
- authors ✓
- concepts ✓
- domains ✓
- fields ✓
- funders ✓
- institutions ✓
- publishers ✓
- sources ✓
- subfields ✓
- topics ✓
- works ✓

## 接下来的步骤

1. **安装 Metabase**（如果还未安装）:
   ```bash
   cd /home/ubuntu/openalex
   ./scripts/setup_metabase.sh
   ```

2. **运行首次 ETL**（如果数据还未转换）:
   ```bash
   cd /home/ubuntu/openalex
   ./run.sh
   ```

3. **设置定时任务**:
   ```bash
   crontab -e
   # 添加上面的 cron 任务
   ```

## 文件权限

所有脚本已设置为可执行 (755):
- ✓ run.sh
- ✓ scripts/sync_openalex.sh
- ✓ scripts/process_data.py
- ✓ scripts/run_pipeline.sh
- ✓ scripts/setup_metabase.sh
- ✓ scripts/install_dependencies.sh
- ✓ scripts/validate_pipeline.sh

## 故障排除

### 如果脚本无法运行
```bash
cd /home/ubuntu/openalex/scripts
chmod +x *.sh *.py
cd ..
chmod +x run.sh
```

### 如果路径引用错误
所有脚本都使用相对路径，基于脚本所在位置自动计算项目根目录。
理论上不应该有路径问题。

### 验证路径配置
```bash
cd /home/ubuntu/openalex
./scripts/validate_pipeline.sh
```

## 总结

✅ 目录重组成功完成
✅ 所有脚本路径已更新
✅ 数据完整性已验证 (2,078 文件)
✅ S3 同步策略已优化
✅ 快捷脚本已创建
✅ 清理工作已完成

**新结构优势**:
- 更清晰的职责分离（scripts、config、data、logs）
- 更易于管理和备份
- 更好的权限控制
- 便于项目迁移

---

**迁移完成！系统已准备就绪。**
