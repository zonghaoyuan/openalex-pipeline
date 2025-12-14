# Metabase配置指南

## 概述

本项目使用Metabase + DuckDB来查询和可视化OpenAlex的Parquet数据。由于数据量巨大（4.6亿+条论文记录），我们采用了特殊的配置来优化性能。

## 系统要求

- **内存**: 至少8GB RAM（推荐16GB+）
- **CPU**: 4核心+
- **存储**: 确保有足够空间存储parquet数据（~800GB）

## 安装步骤

### 1. 下载DuckDB插件

DuckDB插件已配置为自动下载，但如果需要手动下载：

```bash
mkdir -p metabase/plugins
cd metabase/plugins
wget https://github.com/motherduckdb/metabase_duckdb_driver/releases/download/1.4.3.0/duckdb.metabase-driver.jar
chmod 777 ../
```

**重要**: plugins目录需要777权限以便Metabase容器写入。

### 2. 启动Metabase

```bash
cd ~/openalex
sudo docker compose -f config/docker-compose.yml up -d
```

### 3. 访问Metabase

- **直接访问**: `http://SERVER_IP:3000`
- **通过反向代理**: 配置1Panel等工具，后端地址为 `http://localhost:3000`

### 4. 初次配置

1. 创建管理员账户
2. 选择 "I'll add my data later"
3. 进入主界面后，点击右上角齿轮图标 → Admin → Databases
4. 点击 "Add database"

### 5. 配置DuckDB连接

- **Database type**: DuckDB
- **Display name**: OpenAlex
- **Database file**: `/duckdb/openalex.duckdb`
- 点击 "Save"

## 数据查询

### 重要说明

**不要直接浏览大表**！由于数据量巨大，直接点击表名会导致超时。请使用SQL查询。

### 推荐的查询方式

#### 1. 查询小表（测试连接）

```sql
-- 查询domains表（仅4条记录）
SELECT * FROM read_parquet('/data/domains/**/*.parquet');

-- 查询institutions（10万+记录）
SELECT 
    id,
    display_name,
    country_code,
    works_count
FROM read_parquet('/data/institutions/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true)
LIMIT 100;
```

#### 2. 查询works表（避免超时）

**错误方式**（会超时）:
```sql
-- ❌ 不要这样做！
SELECT * FROM read_parquet('/data/works/**/*.parquet');
```

**正确方式**（指定列和限制）:
```sql
-- ✅ 只查询需要的列
SELECT 
    id,
    title,
    publication_year,
    publication_date,
    cited_by_count
FROM read_parquet('/data/works/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true,
                   columns=['id', 'title', 'publication_year', 
                           'publication_date', 'cited_by_count'])
WHERE publication_year >= 2020
ORDER BY cited_by_count DESC
LIMIT 100;
```

#### 3. 统计查询（优化版）

```sql
-- 按年份统计论文数（限制年份范围）
SELECT 
    publication_year,
    COUNT(*) as paper_count
FROM read_parquet('/data/works/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true,
                   columns=['id', 'publication_year'])
WHERE publication_year >= 2015
GROUP BY publication_year
ORDER BY publication_year DESC;

-- 按国家统计机构数量
SELECT 
    country_code,
    COUNT(*) as institution_count,
    SUM(works_count) as total_works
FROM read_parquet('/data/institutions/**/*.parquet',
                   union_by_name=true)
WHERE country_code IS NOT NULL
GROUP BY country_code
ORDER BY institution_count DESC
LIMIT 20;
```

### 关键参数说明

- `union_by_name=true` - 合并不同schema的parquet文件
- `hive_partitioning=true` - 识别Hive风格的分区（如`updated_date=2024-01-01/`）
- `columns=[...]` - **重要**！只读取需要的列，大幅提升性能并避免类型冲突

## 性能优化建议

### 1. 查询优化

- ✅ 始终使用 `columns` 参数限制读取的列
- ✅ 使用 `WHERE` 过滤条件减少扫描数据量
- ✅ 对大表使用 `LIMIT`
- ❌ 避免 `SELECT *` 查询大表
- ❌ 避免不带过滤的 `GROUP BY` 或 `JOIN`

### 2. 内存配置

Metabase容器已配置4GB堆内存。如果需要调整：

编辑 `config/init-duckdb.sh`，修改最后一行：
```bash
exec java -Xmx8g -Xms2g -jar /app/metabase.jar  # 调整为8GB
```

重新构建：
```bash
sudo docker compose -f config/docker-compose.yml build
sudo docker compose -f config/docker-compose.yml up -d
```

### 3. 查询超时

对于非常大的查询，可能需要增加Metabase的查询超时时间：

在Metabase管理界面：
Admin → Databases → OpenAlex → Advanced options → Additional JDBC connection string options

## 可用的数据表

| 表名 | 记录数 | 描述 | 查询难度 |
|------|--------|------|----------|
| domains | 4 | 学科领域 | ⭐ 很简单 |
| fields | 26 | 学科字段 | ⭐ 很简单 |
| publishers | 16 | 出版商 | ⭐ 很简单 |
| subfields | 252 | 子学科 | ⭐ 很简单 |
| topics | 4,516 | 主题 | ⭐ 很简单 |
| funders | 32,437 | 资助机构 | ⭐⭐ 简单 |
| concepts | 65,026 | 概念 | ⭐⭐ 简单 |
| institutions | 102,539 | 机构 | ⭐⭐ 简单 |
| sources | 255,250 | 期刊/会议 | ⭐⭐⭐ 中等 |
| authors | 115,794,829 | 作者 | ⭐⭐⭐⭐ 困难 |
| works | 463,041,975 | 论文/作品 | ⭐⭐⭐⭐⭐ 非常困难 |

## 已知问题和解决方案

### 问题1: "花了太长时间" 超时错误

**原因**: 查询的数据量太大

**解决方案**:
- 使用 `columns` 参数限制读取的列
- 添加 `WHERE` 条件过滤数据
- 使用 `LIMIT` 限制返回行数

### 问题2: Schema/类型转换错误

**错误示例**:
```
Conversion Error: failed to cast column "xxx" from type VARCHAR to JSON
```

**原因**: 不同时间分区的parquet文件schema不一致

**解决方案**:
- 使用 `columns` 参数只读取基本类型字段（避免复杂类型如JSON、STRUCT[]）
- 避免查询包含复杂嵌套结构的字段（如`authorships`、`institutions`等）

### 问题3: Metabase服务器错误

**解决方案**:
```bash
# 查看日志
sudo docker logs openalex-metabase --tail=100

# 重启容器
sudo docker compose -f config/docker-compose.yml restart metabase
```

## 维护

### 更新DuckDB插件

```bash
cd metabase/plugins
# 备份旧版本
mv duckdb.metabase-driver.jar duckdb.metabase-driver.jar.old

# 下载新版本
wget https://github.com/motherduckdb/metabase_duckdb_driver/releases/download/VERSION/duckdb.metabase-driver.jar

# 重启Metabase
sudo docker compose -f config/docker-compose.yml restart metabase
```

### 重置Metabase配置

如果需要重置Metabase（保留parquet数据）：

```bash
sudo docker compose -f config/docker-compose.yml down
sudo docker volume rm config_metabase_data
rm -f data/openalex.duckdb*
sudo docker compose -f config/docker-compose.yml up -d
```

## 示例查询集合

### 查找高被引论文

```sql
SELECT 
    title,
    publication_year,
    cited_by_count,
    doi
FROM read_parquet('/data/works/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true,
                   columns=['title', 'publication_year', 'cited_by_count', 'doi'])
WHERE publication_year >= 2020
  AND cited_by_count > 100
ORDER BY cited_by_count DESC
LIMIT 50;
```

### 查找特定机构

```sql
SELECT 
    display_name,
    country_code,
    works_count,
    cited_by_count,
    ror
FROM read_parquet('/data/institutions/**/*.parquet',
                   union_by_name=true)
WHERE display_name LIKE '%Stanford%'
   OR display_name LIKE '%清华%'
   OR display_name LIKE '%Tsinghua%';
```

### 论文趋势分析

```sql
SELECT 
    publication_year,
    COUNT(*) as total_papers,
    AVG(cited_by_count) as avg_citations
FROM read_parquet('/data/works/**/*.parquet',
                   union_by_name=true,
                   hive_partitioning=true,
                   columns=['publication_year', 'cited_by_count'])
WHERE publication_year BETWEEN 2015 AND 2024
GROUP BY publication_year
ORDER BY publication_year;
```

## 技术架构说明

### 为什么使用Debian而非Alpine

官方Metabase镜像基于Alpine Linux（使用musl libc），但DuckDB的Java驱动需要glibc。经过测试，Alpine + gcompat仍然会导致JVM崩溃。

因此本项目使用：
- 基础镜像: `eclipse-temurin:11-jre` (Debian-based)
- DuckDB兼容性: 完全兼容，无需额外配置

### 数据组织

```
data/
├── parquet/          # Parquet数据（挂载到容器 /data/）
│   ├── works/
│   ├── authors/
│   └── ...
└── openalex.duckdb   # DuckDB数据库文件（挂载到容器 /duckdb/）
```

### 容器配置

- **端口**: 3000（映射到宿主机3000）
- **内存**: 4GB JVM堆内存
- **数据卷**: parquet数据只读，DuckDB文件读写

## 故障排除

### Metabase无法启动

```bash
# 检查容器状态
sudo docker ps -a | grep metabase

# 查看详细日志
sudo docker logs openalex-metabase

# 检查端口占用
sudo netstat -tlnp | grep 3000
```

### DuckDB连接失败

检查数据库文件是否存在：
```bash
sudo docker exec openalex-metabase ls -lh /duckdb/
```

### 插件未加载

检查插件目录：
```bash
ls -la metabase/plugins/
sudo docker exec openalex-metabase ls -la /plugins/
```

确保plugins目录有正确权限（777）。
