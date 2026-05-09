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
    echo "启动 FutuOpenD..."
    cd $OPEND_DIR
    nohup $OPEND_CMD -no_monitor=0 -console=0 >> $LOG_DIR/opend.out.log 2>> $LOG_DIR/opend.err.log &
    sleep 1
    if pgrep -f "FutuOpenD" > /dev/null; then
        echo "FutuOpenD 已启动 (PID: $(pgrep -f 'FutuOpenD'))"
    else
        echo "启动失败，请检查日志: $LOG_DIR/opend.err.log"
    fi
}

stop() {
    echo "停止 FutuOpenD..."
    pkill -f "FutuOpenD"
    sleep 1
    if pgrep -f "FutuOpenD" > /dev/null; then
        echo "停止失败，强制杀死进程..."
        pkill -9 -f "FutuOpenD"
    else
        echo "FutuOpenD 已停止"
    fi
}

status() {
    if pgrep -f "FutuOpenD" > /dev/null; then
        echo "FutuOpenD 运行中 (PID: $(pgrep -f 'FutuOpenD'))"
        ps aux | grep -E "FutuOpenD|PID" | grep -v grep
    else
        echo "FutuOpenD 未运行"
    fi
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
    *)
        echo "用法: $0 {start|stop|status|restart|log|enable-rsa|disable-rsa|enable-autostart|disable-autostart}"
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
        exit 1
        ;;
esac
