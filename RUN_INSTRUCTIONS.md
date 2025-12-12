# OpenAlex ETL 运行指南

## 方法一：在 Screen 中运行完整 ETL（推荐）

### 快速启动（一键命令）

```bash
cd /home/ubuntu/openalex
./run_etl_in_screen.sh
```

### 或手动启动

```bash
# 创建 screen 会话并运行 ETL
screen -dmS openalex-etl bash -c "cd /home/ubuntu/openalex && ./run.sh; exec bash"
```

### Screen 常用命令

| 命令 | 说明 |
|------|------|
| `screen -r openalex-etl` | 连接到 ETL 会话 |
| `Ctrl+A` 然后按 `D` | 从会话中分离（ETL 继续运行） |
| `screen -ls` | 列出所有 screen 会话 |
| `screen -S openalex-etl -X quit` | 终止 ETL 会话 |

### 监控进度

#### 方法 1：查看日志
```bash
# 实时查看处理日志
tail -f /home/ubuntu/openalex/logs/etl_process.log

# 查看最近的错误
tail -f /home/ubuntu/openalex/logs/etl_errors.log
```

#### 方法 2：连接到 Screen 会话
```bash
# 连接到运行中的 ETL
screen -r openalex-etl

# 查看实时输出
# 要退出但保持 ETL 运行：按 Ctrl+A 然后按 D
```

#### 方法 3：检查进度
```bash
# 查看已处理的文件数
find /home/ubuntu/openalex/data/parquet -name "*.parquet" | wc -l

# 查看总文件数
find /home/ubuntu/openalex/data/source -name "*.gz" | wc -l
```

### 典型工作流程

```bash
# 1. 启动 ETL
cd /home/ubuntu/openalex
./run_etl_in_screen.sh

# 2. 验证启动成功
screen -ls
# 应该看到: openalex-etl

# 3. 查看实时日志（可选）
tail -f logs/etl_process.log

# 4. 如果需要，连接到 screen 查看
screen -r openalex-etl

# 5. 分离（保持运行）
# 按: Ctrl+A, 然后按: D

# 6. 稍后检查进度
find data/parquet -name "*.parquet" | wc -l

# 7. ETL 完成后，screen 会话会自动保留
# 可以连接查看最终输出
screen -r openalex-etl

# 8. 清理完成的 screen 会话（可选）
screen -S openalex-etl -X quit
```

---

## 方法二：直接运行（前台）

**不推荐用于长时间任务**，因为 SSH 断开会中止进程。

```bash
cd /home/ubuntu/openalex
./run.sh
```

---

## Cron 自动化配置

### 当前配置

✅ **已配置为每天凌晨 2:00（中国时间）执行**

```cron
# 中国时间 2:00 AM = UTC 18:00 (前一天)
0 18 * * * cd /home/ubuntu/openalex && ./run.sh >> ./logs/cron.log 2>&1
```

### 时间说明

| 时区 | 时间 |
|------|------|
| 中国时间 (UTC+8) | 凌晨 2:00 AM |
| UTC 时间 | 前一天 18:00 (6:00 PM) |
| 服务器时间 (UTC) | 前一天 18:00 |

**示例**：
- 中国时间：2025年12月13日 凌晨 2:00
- UTC 时间：2025年12月12日 下午 6:00

### Cron 管理命令

```bash
# 查看当前 crontab
crontab -l

# 编辑 crontab
crontab -e

# 查看 cron 执行日志
tail -f /home/ubuntu/openalex/logs/cron.log

# 查看系统 cron 日志
sudo tail -f /var/log/syslog | grep CRON
```

### 如果需要修改执行时间

| 中国时间 | UTC 时间 | Cron 表达式 |
|----------|----------|-------------|
| 凌晨 1:00 | 前一天 17:00 | `0 17 * * *` |
| 凌晨 2:00 | 前一天 18:00 | `0 18 * * *` ✅ 当前 |
| 凌晨 3:00 | 前一天 19:00 | `0 19 * * *` |
| 凌晨 4:00 | 前一天 20:00 | `0 20 * * *` |

---

## 预计执行时间

### 首次完整运行

- **文件数量**: 2,078 个 .gz 文件
- **已处理**: 76 个（测试）
- **待处理**: 2,002 个
- **预计时间**: 2-6 小时（取决于文件大小）

### 后续增量运行

- **典型情况**: 每天几十个新文件
- **预计时间**: 5-30 分钟
- **机制**: 只处理新增/修改的文件

---

## 进度监控脚本

创建快速检查脚本：

```bash
cat > /home/ubuntu/openalex/check_progress.sh << 'EOF'
#!/bin/bash
echo "=== OpenAlex ETL Progress ==="
echo ""
echo "Source files:     $(find data/source -name '*.gz' | wc -l)"
echo "Processed files:  $(find data/parquet -name '*.parquet' | wc -l)"
echo ""
echo "Parquet size:     $(du -sh data/parquet 2>/dev/null | cut -f1)"
echo ""
echo "Latest log entries:"
tail -5 logs/etl_process.log
EOF

chmod +x /home/ubuntu/openalex/check_progress.sh
```

使用：
```bash
./check_progress.sh
```

---

## 故障排除

### Screen 会话丢失

```bash
# 查找所有 screen 会话
screen -ls

# 如果看不到 openalex-etl，可能进程已完成
# 检查日志确认
tail -50 logs/etl_process.log
```

### ETL 似乎卡住

```bash
# 检查进程是否还在运行
ps aux | grep process_data.py

# 查看最新日志
tail -20 logs/etl_process.log

# 如果需要，可以连接到 screen 查看
screen -r openalex-etl
```

### 磁盘空间不足

```bash
# 检查可用空间
df -h /home/ubuntu/openalex

# 如果空间不足，清理旧日志
find logs -name "*.log" -mtime +7 -delete
```

### Cron 未执行

```bash
# 检查 cron 服务状态
sudo systemctl status cron

# 查看 cron 日志
sudo tail -f /var/log/syslog | grep CRON

# 手动测试 cron 命令
cd /home/ubuntu/openalex && ./run.sh
```

---

## 推荐工作流程

### 首次完整运行

```bash
# 1. 启动 screen 会话
cd /home/ubuntu/openalex
./run_etl_in_screen.sh

# 2. 验证启动
screen -ls
tail -10 logs/etl_process.log

# 3. 定期检查进度（可选）
watch -n 300 './check_progress.sh'  # 每5分钟检查一次

# 4. 或者查看实时日志
tail -f logs/etl_process.log
```

### 日常运维

```bash
# 让 cron 自动运行即可
# 定期检查日志
tail -20 logs/cron.log
tail -20 logs/etl_process.log

# 偶尔检查是否有失败文件
# (需要 Python)
python3 -c "
import sqlite3
con = sqlite3.connect('state/etl_state.db')
failed = con.execute('SELECT COUNT(*) FROM failed_files').fetchone()[0]
print(f'Failed files: {failed}')
"
```

---

## 性能优化建议

### 如果处理太慢

1. **检查系统资源**:
   ```bash
   htop  # 或 top
   ```

2. **检查磁盘 I/O**:
   ```bash
   iostat -x 5
   ```

3. **考虑调整 DuckDB 内存**（编辑 `scripts/process_data.py`）:
   ```python
   # 增加内存限制
   duckdb.connect(':memory:', config={'memory_limit': '32GB'})
   ```

---

## 快速参考

| 任务 | 命令 |
|------|------|
| 启动 ETL | `./run_etl_in_screen.sh` |
| 查看进度 | `./check_progress.sh` |
| 实时日志 | `tail -f logs/etl_process.log` |
| 连接 screen | `screen -r openalex-etl` |
| 分离 screen | `Ctrl+A` + `D` |
| 检查 cron | `crontab -l` |
| 查看 cron 日志 | `tail -f logs/cron.log` |

---

**准备就绪！现在可以开始运行了！** 🚀

推荐首次运行命令：
```bash
cd /home/ubuntu/openalex && ./run_etl_in_screen.sh
```
