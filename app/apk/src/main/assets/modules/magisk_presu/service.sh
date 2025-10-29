#!/system/bin/sh
# Magisk Pre-SU Authorization Service Script

MODDIR=${0%/*}
PACKAGE_NAME="com.example.test"
MAGISK_DB="/data/adb/magisk.db"
LOG_FILE="/data/local/tmp/magisk_presu.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== Magisk Pre-SU Service Started ==="

# 等待系统启动完成
sleep 30

# 等待 Magisk 数据库就绪
while [ ! -f "$MAGISK_DB" ]; do
    log "Waiting for Magisk database..."
    sleep 5
done

log "Magisk database found"

# 授权 adb shell su (shell 用户 UID: 2000)
grant_shell_su() {
    SHELL_UID=2000

    # 检查是否已经授权
    EXISTING=$(sqlite3 "$MAGISK_DB" "SELECT uid FROM policies WHERE uid=$SHELL_UID;" 2>/dev/null)

    if [ -z "$EXISTING" ]; then
        log "Granting su permission to shell user (UID: $SHELL_UID) for adb shell su"

        sqlite3 "$MAGISK_DB" <<EOF
INSERT OR REPLACE INTO policies (uid, policy, until, logging, notification)
VALUES ($SHELL_UID, 2, 0, 1, 0);
EOF

        if [ $? -eq 0 ]; then
            log "Successfully granted su permission to shell user (UID: $SHELL_UID)"

            # 验证插入结果
            VERIFY=$(sqlite3 "$MAGISK_DB" "SELECT uid, policy FROM policies WHERE uid=$SHELL_UID;" 2>/dev/null)
            log "Verification: $VERIFY"
            return 0
        else
            log "Failed to grant su permission to shell user"
            return 1
        fi
    else
        log "Shell user (UID: $SHELL_UID) already has su permission"
        return 0
    fi
}

# 立即授权 adb shell su
grant_shell_su

# 检查包名是否已安装并获取 UID
check_and_grant() {
    # 方法1: 从 packages.list 获取 UID（更可靠）
    APP_UID=$(grep "^$PACKAGE_NAME " /data/system/packages.list 2>/dev/null | awk '{print $2}')

    # 方法2: 如果方法1失败，使用 dumpsys（备用）
    if [ -z "$APP_UID" ]; then
        APP_UID=$(dumpsys package "$PACKAGE_NAME" 2>/dev/null | grep "userId=" | head -n 1 | sed 's/.*userId=\([0-9]*\).*/\1/')
    fi

    if [ -n "$APP_UID" ]; then
        log "Package $PACKAGE_NAME found with UID: $APP_UID"

        # 检查是否已经授权（Magisk v29.0 只用 uid 作为主键）
        EXISTING=$(sqlite3 "$MAGISK_DB" "SELECT uid FROM policies WHERE uid=$APP_UID;" 2>/dev/null)

        if [ -z "$EXISTING" ]; then
            log "Granting su permission to UID: $APP_UID ($PACKAGE_NAME)"

            # 添加授权记录（Magisk v29.0 policies 表结构）
            # uid: 应用的 UID
            # policy: 2 = allow (允许)
            # until: 0 = permanent (永久有效)
            # logging: 1 = enable logging (启用日志)
            # notification: 1 = show notification (显示通知)
            sqlite3 "$MAGISK_DB" <<EOF
INSERT OR REPLACE INTO policies (uid, policy, until, logging, notification)
VALUES ($APP_UID, 2, 0, 1, 1);
EOF

            if [ $? -eq 0 ]; then
                log "Successfully granted su permission to UID: $APP_UID ($PACKAGE_NAME)"

                # 验证插入结果
                VERIFY=$(sqlite3 "$MAGISK_DB" "SELECT uid, policy FROM policies WHERE uid=$APP_UID;" 2>/dev/null)
                log "Verification: $VERIFY"
                return 0
            else
                log "Failed to grant su permission to UID: $APP_UID"
                return 1
            fi
        else
            log "UID: $APP_UID ($PACKAGE_NAME) already has su permission"
            return 0
        fi
    else
        return 1
    fi
}

# 首次检查
if check_and_grant; then
    log "Initial check completed successfully"
else
    log "Package not installed yet, starting monitoring..."

    # 监控应用安装（每30秒检查一次，持续24小时）
    COUNTER=0
    MAX_CHECKS=2880  # 24小时 = 2880 * 30秒

    while [ $COUNTER -lt $MAX_CHECKS ]; do
        sleep 30

        if check_and_grant; then
            log "Package installed and authorized, stopping monitor"
            break
        fi

        COUNTER=$((COUNTER + 1))
    done

    if [ $COUNTER -ge $MAX_CHECKS ]; then
        log "Monitoring timeout (24 hours), stopping"
    fi
fi

log "=== Magisk Pre-SU Service Finished ==="
