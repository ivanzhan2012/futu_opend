#!/bin/bash
# FutuOpenD 控制脚本
# 用法: opend_ctl.sh {start|stop|status|restart|log|enable-rsa|disable-rsa|enable-autostart|disable-autostart}

OPEND_CMD="/app/FutuOpenD/FutuOpenD"
OPEND_DIR="/app/FutuOpenD"
LOG_DIR="/var/log/supervisor"
PRIVATE_KEY_SRC="/opt/.futu_private_key.pem"
PRIVATE_KEY_DST="$OPEND_DIR/.futu_private_key.pem"
XML_FILE="$OPEND_DIR/FutuOpenD.xml"
SUPERVISOR_CONF="/etc/supervisor/conf.d/supervisor_opend.conf"

start() {
    echo "启动 FutuOpenD (通过 supervisor 管理) ..."
    supervisorctl start opend
}

stop() {
    echo "停止 FutuOpenD (通过 supervisor 管理) ..."
    supervisorctl stop opend
}

status() {
    echo "=== Supervisor 管理状态 ==="
    supervisorctl status opend
    echo ""
    if [ -f "$SUPERVISOR_CONF" ] && grep -q "autostart=true" "$SUPERVISOR_CONF"; then
        echo "Supervisor 自动拉起: 已启用（容器重启时 opend 将自动启动）"
    else
        echo "Supervisor 自动拉起: 已禁用（容器重启时 opend 不会自动启动）"
    fi
}

log() {
    echo "=== 最近日志 (stdout) ==="
    tail -20 $LOG_DIR/opend.out.log 2>/dev/null || echo "无日志文件"
    echo ""
    echo "=== 最近日志 (stderr) ==="
    tail -20 $LOG_DIR/opend.err.log 2>/dev/null || echo "无日志文件"
}

enable_rsa() {
    if [ ! -f "$XML_FILE" ]; then
        echo "错误: 未找到 $XML_FILE，请确认 FutuOpenD 已初始化"
        exit 1
    fi

    if [ ! -f "$PRIVATE_KEY_SRC" ]; then
        echo "错误: 私钥文件 $PRIVATE_KEY_SRC 未挂载或不存在"
        echo "请确认 .env 中 FUTU_PRIVATE_KEY 已配置且文件存在，然后重建容器"
        exit 1
    fi

    echo "复制私钥 ..."
    cp "$PRIVATE_KEY_SRC" "$PRIVATE_KEY_DST"
    chmod 600 "$PRIVATE_KEY_DST"
    chown ubuntu:ubuntu "$PRIVATE_KEY_DST"

    echo "注入私钥到 XML ..."
    if grep -q "<!-- <rsa_private_key>" "$XML_FILE"; then
        # 当前已注释（禁用状态）→ 取消注释并写入路径
        sed -i "s|<!-- <rsa_private_key>[^<]*</rsa_private_key> -->|<rsa_private_key>${PRIVATE_KEY_DST}</rsa_private_key>|" "$XML_FILE"
    else
        # 已启用但可能路径不同 → 更新路径（仅对非注释行操作）
        sed -i '/<!--/!s|<rsa_private_key>[^<]*</rsa_private_key>|<rsa_private_key>'"${PRIVATE_KEY_DST}"'</rsa_private_key>|' "$XML_FILE"
    fi

    echo "RSA 加密已启用，重启 FutuOpenD 使配置生效 ..."
    stop
    sleep 2
    start
}

disable_rsa() {
    if [ ! -f "$XML_FILE" ]; then
        echo "错误: 未找到 $XML_FILE，请确认 FutuOpenD 已初始化"
        exit 1
    fi

    if grep -q "<!-- <rsa_private_key>" "$XML_FILE"; then
        echo "RSA 加密已是禁用状态，无需操作"
        return
    fi

    echo "注释掉 XML 中的私钥配置 ..."
    # 仅替换未注释行，避免误操作已注释行
    sed -i '/<!--/!s|<rsa_private_key>[^<]*</rsa_private_key>|<!-- <rsa_private_key>disabled</rsa_private_key> -->|' "$XML_FILE"

    if [ -f "$PRIVATE_KEY_DST" ]; then
        rm -f "$PRIVATE_KEY_DST"
        echo "已删除容器内私钥副本 $PRIVATE_KEY_DST"
    fi

    echo "RSA 加密已禁用，重启 FutuOpenD 使配置生效 ..."
    stop
    sleep 2
    start
}

first_login() {
    if pgrep -f "FutuOpenD" > /dev/null; then
        echo "检测到 FutuOpenD 正在运行，先停止..."
        stop
        sleep 2
    fi

    echo ""
    echo "============================================================"
    echo "  首次登录交互模式"
    echo "  FutuOpenD 将以控制台模式前台运行，请："
    echo "  1. 等待登录提示出现"
    echo "  2. 按提示输入手机短信验证码完成登录"
    echo "  3. 登录成功后，输入 exit 退出首次登录"
    echo "  4. 退出后，重新执行 opend_ctl.sh start 或 restart 正常启动"
    echo "============================================================"
    echo ""

    cd "$OPEND_DIR"
    runuser -u ubuntu -- "$OPEND_CMD"

    # 交互式登录结束后，检查最近 GTW 日志验证是否真正登录成功
    echo ""
    local log_dir="/home/ubuntu/.com.futunn.FutuOpenD/Log"
    local latest_gtw
    latest_gtw=$(ls -t ${log_dir}/GTWLog_*.log 2>/dev/null | head -1)

    if [ -n "$latest_gtw" ] && grep -q 'ProgramStatusType_Ready' "$latest_gtw" 2>/dev/null; then
        echo "[OK] GTW 日志确认首次登录成功"
    elif [ -n "$latest_gtw" ] && grep -q 'req_phone_verify_code' "$latest_gtw" 2>/dev/null; then
        echo "[WARN] 最近会话仍需短信验证，首次登录未完成，请重新执行 first-login"
    else
        echo "[WARN] GTW 日志未检测到明确的登录结果，请重新执行 first-login"
    fi
}

enable_autostart() {
    if [ ! -f "$SUPERVISOR_CONF" ]; then
        echo "错误: 未找到 $SUPERVISOR_CONF"
        exit 1
    fi
    if grep -q "autostart=true" "$SUPERVISOR_CONF"; then
        echo "Supervisor 自动拉起已是启用状态，无需操作"
        return
    fi
    sed -i 's/autostart=false/autostart=true/' "$SUPERVISOR_CONF"
    echo "✓ 已启用 Supervisor 自动拉起 opend"
    echo "  下次容器重启时将自动启动 opend"
    echo "  如需立即启动，请运行: $0 start"
}

disable_autostart() {
    if [ ! -f "$SUPERVISOR_CONF" ]; then
        echo "错误: 未找到 $SUPERVISOR_CONF"
        exit 1
    fi
    if grep -q "autostart=false" "$SUPERVISOR_CONF"; then
        echo "Supervisor 自动拉起已是禁用状态，无需操作"
        return
    fi
    sed -i 's/autostart=true/autostart=false/' "$SUPERVISOR_CONF"
    echo "✓ 已禁用 Supervisor 自动拉起 opend"
    echo "  下次容器重启时 opend 不会自动启动"
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    log)
        log
        ;;
    enable-rsa)
        enable_rsa
        ;;
    disable-rsa)
        disable_rsa
        ;;
    enable-autostart)
        enable_autostart
        ;;
    disable-autostart)
        disable_autostart
        ;;
    first-login)
        first_login
        ;;
    *)
        echo "用法: $0 {start|stop|status|restart|log|enable-rsa|disable-rsa|enable-autostart|disable-autostart|first-login}"
        echo ""
        echo "  start            - 启动 FutuOpenD"
        echo "  stop             - 停止 FutuOpenD"
        echo "  status           - 查看运行状态及 supervisor 自动拉起状态"
        echo "  restart          - 重启 FutuOpenD"
        echo "  log              - 查看最近日志"
        echo "  enable-rsa       - 启用 RSA 加密（注入私钥并重启）"
        echo "  disable-rsa      - 禁用 RSA 加密（注释私钥并重启）"
        echo "  enable-autostart - 启用 supervisor 自动拉起（容器重启时自动启动 opend）"
        echo "  disable-autostart- 禁用 supervisor 自动拉起（容器重启时不启动 opend）"
        echo "  first-login      - 首次登录模式（交互式前台运行，用于输入短信验证码）"
        exit 1
        ;;
esac
