#!/bin/bash
###############################################################################
# Email Notification Script for OpenAlex Data Pipeline
# Usage: send_email_notification.sh <status> [stats_file]
#   status: success | failure
#   stats_file: JSON file with processing statistics (optional)
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load email configuration
source "${PROJECT_ROOT}/config/email_config.sh"

# Parameters
STATUS="${1:-}"
STATS_FILE="${2:-}"

if [ -z "$STATUS" ]; then
    echo "Usage: $0 <success|failure> [stats_file]"
    exit 1
fi

# Get current timestamp
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S UTC")
CHINA_TIME=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")

###############################################################################
# Function: Generate success email
###############################################################################
generate_success_email() {
    local stats_file="$1"

    # Read statistics if available
    if [ -f "$stats_file" ]; then
        FILES_PROCESSED=$(jq -r '.files_processed // 0' "$stats_file" 2>/dev/null || echo "0")
        FILES_SKIPPED=$(jq -r '.files_skipped // 0' "$stats_file" 2>/dev/null || echo "0")
        RECORDS_ADDED=$(jq -r '.records_added // 0' "$stats_file" 2>/dev/null || echo "0")
        DURATION=$(jq -r '.duration_seconds // 0' "$stats_file" 2>/dev/null || echo "0")
        SYNC_FILES=$(jq -r '.sync_files // 0' "$stats_file" 2>/dev/null || echo "0")
        SYNC_SIZE=$(jq -r '.sync_size_mb // "0"' "$stats_file" 2>/dev/null || echo "0")
        SYNC_DURATION=$(jq -r '.sync_duration_seconds // 0' "$stats_file" 2>/dev/null || echo "0")
    else
        FILES_PROCESSED="N/A"
        FILES_SKIPPED="N/A"
        RECORDS_ADDED="N/A"
        DURATION="N/A"
        SYNC_FILES="N/A"
        SYNC_SIZE="N/A"
        SYNC_DURATION="N/A"
    fi

    # Format duration
    if [ "$DURATION" != "N/A" ] && [ "$DURATION" -gt 0 ]; then
        DURATION_MIN=$((DURATION / 60))
        DURATION_SEC=$((DURATION % 60))
        DURATION_STR="${DURATION_MIN}分${DURATION_SEC}秒"
    else
        DURATION_STR="N/A"
    fi

    if [ "$SYNC_DURATION" != "N/A" ] && [ "$SYNC_DURATION" -gt 0 ]; then
        SYNC_MIN=$((SYNC_DURATION / 60))
        SYNC_SEC=$((SYNC_DURATION % 60))
        SYNC_DURATION_STR="${SYNC_MIN}分${SYNC_SEC}秒"
    else
        SYNC_DURATION_STR="N/A"
    fi

    # Get storage info
    PARQUET_SIZE=$(du -sh "${PROJECT_ROOT}/data/parquet" 2>/dev/null | cut -f1 || echo "N/A")
    PARQUET_FILES=$(find "${PROJECT_ROOT}/data/parquet" -name "*.parquet" 2>/dev/null | wc -l || echo "0")
    AVAILABLE_SPACE=$(df -h "${PROJECT_ROOT}" | tail -1 | awk '{print $4}')

    # Generate entity breakdown if available
    ENTITY_BREAKDOWN=""
    if [ -f "$stats_file" ] && command -v jq &> /dev/null; then
        ENTITY_BREAKDOWN=$(jq -r '
            .entity_stats // {} |
            to_entries |
            map("  • \(.key): \(.value.files)个文件，\(.value.records)条记录") |
            join("\n")
        ' "$stats_file" 2>/dev/null || echo "")
    fi

    # Generate email body
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 OpenAlex 数据管道 - 更新报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

执行时间：${TIMESTAMP}
中国时间：${CHINA_TIME}
任务状态：✅ 成功完成

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 同步统计
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

S3 同步：
  • 检测到变化文件：${SYNC_FILES} 个
  • 下载数据量：${SYNC_SIZE} MB
  • 同步耗时：${SYNC_DURATION_STR}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 ETL 处理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

处理统计：
  • 已处理文件：${FILES_PROCESSED} 个
  • 跳过文件（无变化）：${FILES_SKIPPED} 个
  • 新增/更新记录：${RECORDS_ADDED} 条
  • 处理耗时：${DURATION_STR}

$(if [ -n "$ENTITY_BREAKDOWN" ]; then
    echo "实体分布："
    echo "$ENTITY_BREAKDOWN"
fi)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 存储状态
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Parquet 数据：
  • 总大小：${PARQUET_SIZE}
  • 文件数：${PARQUET_FILES} 个
  • 可用空间：${AVAILABLE_SPACE}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 详细日志
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

日志位置：/home/ubuntu/openalex/logs/
  • 处理日志：etl_process.log
  • Cron 日志：cron.log

查看最新日志：
  tail -100 /home/ubuntu/openalex/logs/cron.log

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

下次同步：明天 02:00 中国时间

--
此邮件由 OpenAlex 数据管道自动发送
${SENDER_EMAIL}
EOF
}

###############################################################################
# Function: Generate failure email
###############################################################################
generate_failure_email() {
    local stats_file="$1"

    # Get error information
    ERROR_LOG="${PROJECT_ROOT}/logs/etl_errors.log"
    if [ -f "$ERROR_LOG" ]; then
        LAST_ERRORS=$(tail -20 "$ERROR_LOG")
    else
        LAST_ERRORS="错误日志文件不存在"
    fi

    # Try to get partial stats
    if [ -f "$stats_file" ]; then
        FILES_PROCESSED=$(jq -r '.files_processed // 0' "$stats_file" 2>/dev/null || echo "0")
        FILES_FAILED=$(jq -r '.files_failed // 0' "$stats_file" 2>/dev/null || echo "0")
        ERROR_MSG=$(jq -r '.error_message // "Unknown error"' "$stats_file" 2>/dev/null || echo "Unknown error")
    else
        FILES_PROCESSED="N/A"
        FILES_FAILED="N/A"
        ERROR_MSG="统计信息不可用"
    fi

    # Generate email body
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ OpenAlex 数据管道 - 错误报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

执行时间：${TIMESTAMP}
中国时间：${CHINA_TIME}
任务状态：❌ 失败

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚨 错误信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${ERROR_MSG}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 执行进度
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

已完成：${FILES_PROCESSED} 个文件
失败文件：${FILES_FAILED} 个

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 建议操作
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 检查系统资源：
   df -h /home/ubuntu/openalex
   free -h

2. 查看错误日志：
   tail -50 /home/ubuntu/openalex/logs/etl_errors.log

3. 手动重试（可选）：
   cd /home/ubuntu/openalex && ./run.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 最近错误日志（最后 20 行）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${LAST_ERRORS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

请尽快检查并修复问题。

--
此邮件由 OpenAlex 数据管道自动发送
${SENDER_EMAIL}
EOF
}

###############################################################################
# Main execution
###############################################################################

# Generate email content based on status
if [ "$STATUS" = "success" ]; then
    SUBJECT="✅ OpenAlex 数据更新完成 - $(date +%Y-%m-%d)"
    EMAIL_BODY=$(generate_success_email "$STATS_FILE")
elif [ "$STATUS" = "failure" ]; then
    SUBJECT="⚠️ OpenAlex 数据更新失败 - 需要关注"
    EMAIL_BODY=$(generate_failure_email "$STATS_FILE")
else
    echo "Error: Invalid status '$STATUS'. Must be 'success' or 'failure'."
    exit 1
fi

# Send email using mail command (uses msmtp via msmtp-mta)
# Important: Must specify From address to match authenticated domain
echo "$EMAIL_BODY" | mail -s "$SUBJECT" -a "From: ${SENDER_EMAIL}" "$RECIPIENT_EMAIL"

# Log the notification
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Email notification sent: $STATUS to $RECIPIENT_EMAIL" >> "${PROJECT_ROOT}/logs/notifications.log"

echo "Email notification sent successfully to $RECIPIENT_EMAIL"
