#!/bin/bash
# 简化初始化 - 只创建空数据库，不预创建视图

DB_PATH="/duckdb/openalex.duckdb"

# 等待parquet数据挂载
sleep 2

# 安装Python和DuckDB（如果尚未安装）
if ! command -v python3 &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq python3 python3-pip > /dev/null 2>&1
    pip3 install --break-system-packages -q duckdb > /dev/null 2>&1
fi

# 创建数据库并初始化视图
python3 << 'PYTHON_SCRIPT'
import duckdb
import os

db_path = '/duckdb/openalex.duckdb'

# 删除旧数据库
if os.path.exists(db_path):
    try:
        os.remove(db_path)
    except:
        pass

# 创建数据库连接
con = duckdb.connect(db_path)

# 读取并执行视图创建SQL
try:
    with open('/app/create_views.sql', 'r') as f:
        sql_content = f.read()

    # 移除注释并分割SQL语句
    lines = sql_content.split('\n')
    clean_lines = []
    for line in lines:
        # 移除单行注释
        if '--' in line:
            line = line[:line.index('--')]
        if line.strip():
            clean_lines.append(line)

    clean_sql = '\n'.join(clean_lines)
    statements = [s.strip() for s in clean_sql.split(';') if s.strip()]

    view_count = 0
    for stmt in statements:
        if stmt:
            try:
                con.execute(stmt)
                # 提取视图名称用于日志
                if 'CREATE' in stmt.upper() and 'VIEW' in stmt.upper():
                    view_name = stmt.split('VIEW')[1].split('AS')[0].strip()
                    print(f"✓ Created view: {view_name}")
                    view_count += 1
            except Exception as e:
                print(f"✗ Error: {str(e)[:100]}")

    print(f"\n✓ Database initialized with {view_count} views")

except Exception as e:
    print(f"✗ Error reading SQL file: {e}")
    print("Creating empty database as fallback")

con.close()
PYTHON_SCRIPT

echo "Database initialization complete!"

# 启动Metabase
# 专用服务器配置：64GB RAM，分配48GB堆内存用于大规模数据查询
# 容器限制56GB，堆内存48GB，预留8GB给堆外内存和DuckDB缓冲区
exec java -Xmx48g -Xms8g -jar /app/metabase.jar
