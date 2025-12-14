# OpenAlex项目配置清单

本文档记录了项目从初始状态到完全可用所需的所有配置修改。

## 核心配置文件

### 1. docker-compose.yml
**位置**: `config/docker-compose.yml`

**关键修改**:
```yaml
services:
  metabase:
    build:
      context: .
      dockerfile: Dockerfile.metabase
    image: openalex-metabase:custom
    
    # 端口映射 - 允许反向代理访问
    ports:
      - "3000:3000"  # 从 "127.0.0.1:3000:3000" 改为此
    
    # 数据卷挂载
    volumes:
      - ../data/parquet:/data:ro
      - ../data/openalex.duckdb:/duckdb/openalex.duckdb:rw  # 新增
      - ../metabase/plugins:/plugins
      - metabase_data:/metabase-data
```

**状态**: ✅ 已配置

### 2. Dockerfile.metabase
**位置**: `config/Dockerfile.metabase`

**用途**: 构建基于Debian的Metabase镜像（解决Alpine与DuckDB的兼容性问题）

**内容**:
- 基础镜像: `eclipse-temurin:11-jre` (Debian-based)
- Metabase版本: v0.51.5
- 包含初始化脚本: `init-duckdb.sh`

**状态**: ✅ 已创建

### 3. init-duckdb.sh
**位置**: `config/init-duckdb.sh`

**用途**: Metabase启动时自动初始化DuckDB数据库

**功能**:
- 创建空的DuckDB数据库文件
- 设置Java堆内存为4GB (`-Xmx4g -Xms1g`)
- 启动Metabase服务

**权限**: 需要可执行 (`chmod +x`)

**状态**: ✅ 已创建

### 4. DuckDB插件
**位置**: `metabase/plugins/duckdb.metabase-driver.jar`

**版本**: 1.4.3.0
**来源**: https://github.com/motherduckdb/metabase_duckdb_driver/releases

**目录权限**: `chmod 777 metabase/plugins/` （重要！）

**状态**: ✅ 已下载

## 数据配置

### Parquet数据
**位置**: `data/parquet/`

**结构**:
```
data/parquet/
├── works/          # 463M+ 记录
├── authors/        # 115M+ 记录
├── institutions/   # 102K+ 记录
├── sources/        # 255K+ 记录
└── ... (其他实体)
```

**容器内路径**: `/data/`（只读挂载）

**状态**: ✅ 已生成（通过ETL）

### DuckDB数据库
**位置**: `data/openalex.duckdb`

**用途**: Metabase连接的数据库文件

**容器内路径**: `/duckdb/openalex.duckdb`

**初始化**: 容器启动时自动创建

**状态**: ✅ 自动生成

## 环境配置

### Docker环境
- Docker版本: 要求支持 `docker compose`
- 用户权限: 需要sudo或docker组权限

### 系统要求
- 内存: 至少8GB（推荐16GB+）
- 存储: 至少2TB（parquet ~800GB + 源数据）
- CPU: 4核心+

## 网络配置

### 端口映射
- Metabase: `0.0.0.0:3000 -> 3000` （允许外部访问）

### 反向代理配置（可选）
**1Panel配置示例**:
- 后端地址: `http://localhost:3000`
- 协议: HTTP

## 文档文件

### 新增文档
1. ✅ `METABASE_SETUP.md` - Metabase配置和使用完整指南
2. ✅ `docs/CONFIGURATION_CHECKLIST.md` - 本文档

### 需要更新的文档
1. 📝 `README.md` - 添加Metabase章节
2. 📝 `README.en.md` - 英文版更新

## 常见问题修复记录

### 问题1: Alpine + DuckDB兼容性
**症状**: JVM崩溃，`malloc_init_hard` 错误

**原因**: DuckDB需要glibc，Alpine使用musl libc

**解决**: 使用Debian基础镜像（eclipse-temurin）

**状态**: ✅ 已解决

### 问题2: Parquet路径不匹配
**症状**: `No files found that match the pattern`

**原因**: 视图使用宿主机路径，容器内路径不同

**解决**: 不预创建视图，直接SQL查询parquet文件

**状态**: ✅ 已解决

### 问题3: Schema类型冲突
**症状**: `Conversion Error: failed to cast column`

**原因**: 不同分区的parquet文件schema不一致

**解决**: 使用`columns`参数限制读取的列，避免复杂类型

**状态**: ✅ 已解决（通过文档指导）

### 问题4: 查询超时
**症状**: works表查询花费太长时间

**原因**: 4.6亿条记录的全表扫描

**解决**: 
- 增加Java堆内存到4GB
- 使用`columns`参数优化
- 添加WHERE条件和LIMIT

**状态**: ✅ 已优化

### 问题5: plugins目录权限
**症状**: DuckDB插件未加载

**原因**: Metabase容器无法写入plugins目录

**解决**: `chmod 777 metabase/plugins/`

**状态**: ✅ 已解决

## 验证清单

部署完成后，请验证：

- [ ] Metabase容器状态为`healthy`
  ```bash
  sudo docker ps | grep metabase
  ```

- [ ] DuckDB插件已加载
  ```bash
  sudo docker logs openalex-metabase | grep "Registered driver :duckdb"
  ```

- [ ] 数据库文件已创建
  ```bash
  sudo docker exec openalex-metabase ls -lh /duckdb/
  ```

- [ ] Parquet数据可访问
  ```bash
  sudo docker exec openalex-metabase ls /data/
  ```

- [ ] Metabase Web界面可访问
  - 访问: `http://SERVER_IP:3000`

- [ ] DuckDB连接成功
  - Database file: `/duckdb/openalex.duckdb`

- [ ] 查询测试通过
  ```sql
  SELECT * FROM read_parquet('/data/domains/**/*.parquet');
  ```

## 部署命令摘要

```bash
# 1. 确保ETL已完成，parquet数据已生成
find data/parquet -name "*.parquet" | wc -l  # 应该有2000+个文件

# 2. 确保DuckDB插件存在
ls -lh metabase/plugins/duckdb.metabase-driver.jar

# 3. 设置plugins目录权限
chmod 777 metabase/plugins/

# 4. 构建并启动Metabase
cd ~/openalex
sudo docker compose -f config/docker-compose.yml build
sudo docker compose -f config/docker-compose.yml up -d

# 5. 等待启动（约30秒）
sleep 30

# 6. 验证状态
sudo docker ps | grep metabase
sudo docker logs openalex-metabase | grep "Metabase Initialization COMPLETE"

# 7. 访问Metabase
echo "访问: http://$(hostname -I | awk '{print $1}'):3000"
```

## 回滚方案

如果需要重置Metabase：

```bash
# 停止并删除容器
sudo docker compose -f config/docker-compose.yml down

# 删除Metabase数据（保留parquet）
sudo docker volume rm config_metabase_data
rm -f data/openalex.duckdb*

# 重新启动
sudo docker compose -f config/docker-compose.yml up -d
```

## 维护建议

### 定期检查
- 每月检查DuckDB插件更新
- 每周检查Metabase容器状态
- 监控磁盘空间使用

### 日志管理
```bash
# 查看Metabase日志
sudo docker logs openalex-metabase --tail=100

# 如果日志过大，可以清理
sudo docker compose -f config/docker-compose.yml restart metabase
```

### 性能监控
```bash
# 检查容器资源使用
sudo docker stats openalex-metabase --no-stream
```

## 已知限制

1. **大表查询**: works和authors表非常大，需要优化查询
2. **Schema不一致**: 历史数据可能有不同的schema
3. **内存限制**: 复杂查询可能需要更多内存
4. **查询超时**: 全表扫描可能超时

## 更新历史

- 2025-12-13: 初始版本，记录所有配置
- 修复Alpine兼容性问题，改用Debian镜像
- 优化查询性能，增加内存配置
