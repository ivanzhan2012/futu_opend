#!/bin/bash
OPEND_CMD="/app/FutuOpenD/FutuOpenD"
OPEND_DIR="/app/FutuOpenD"
PRIVATE_KEY_SRC="/opt/.futu_private_key.pem"
PRIVATE_KEY_DST="$OPEND_DIR/.futu_private_key.pem"
XML_FILE="$OPEND_DIR/FutuOpenD.xml"
LOG_DIR="/home/ubuntu/.com.futunn.FutuOpenD/Log"

status() {
    echo "=== FutuOpenD 进程状态 ==="
    local pid
    pid=$(pgrep -x FutuOpenD 2>/dev/null || true)
    if [ -n "$pid" ]; then
        echo "FutuOpenD 运行中 (PID: $pid)"
    else
        echo "FutuOpenD 未运行"
    fi
}

log() {
    local latest
    latest=$(ls -t "$LOG_DIR"/GTWLog_*.log 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo "=== 最近日志: $latest ==="
        tail -30 "$latest"
    else
        echo "暂无日志文件"
    fi
}

enable_rsa() {
    if [ ! -f "$XML_FILE" ]; then
        echo "错误: 未找到 $XML_FILE"
        exit 1
    fi
    if [ ! -f "$PRIVATE_KEY_SRC" ]; then
        echo "错误: 私钥文件 $PRIVATE_KEY_SRC 未挂载或不存在"
        exit 1
    fi
    echo "复制私钥 ..."
    cp "$PRIVATE_KEY_SRC" "$PRIVATE_KEY_DST"
    chmod 600 "$PRIVATE_KEY_DST"
    chown ubuntu:ubuntu "$PRIVATE_KEY_DST"
    echo "注入私钥到 XML ..."
    if grep -q "<!-- <rsa_private_key>" "$XML_FILE"; then
        sed -i "s|<!-- <rsa_private_key>[^<]*</rsa_private_key> -->|<rsa_private_key>${PRIVATE_KEY_DST}</rsa_private_key>|" "$XML_FILE"
    else
        sed -i '/<!--/!s|<rsa_private_key>[^<]*</rsa_private_key>|<rsa_private_key>'"${PRIVATE_KEY_DST}"'</rsa_private_key>|' "$XML_FILE"
    fi
    echo "RSA 加密已启用，请重启容器使配置生效"
}

disable_rsa() {
    if [ ! -f "$XML_FILE" ]; then
        echo "错误: 未找到 $XML_FILE"
        exit 1
    fi
    if grep -q "<!-- <rsa_private_key>" "$XML_FILE"; then
        echo "RSA 加密已是禁用状态"
        return
    fi
    sed -i '/<!--/!s|<rsa_private_key>[^<]*</rsa_private_key>|<!-- <rsa_private_key>disabled</rsa_private_key> -->|' "$XML_FILE"
    [ -f "$PRIVATE_KEY_DST" ] && rm -f "$PRIVATE_KEY_DST"
    echo "RSA 加密已禁用，请重启容器使配置生效"
}

case "$1" in
    status)
        status
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
    *)
        echo "用法: $0 {status|log|enable-rsa|disable-rsa}"
        echo ""
        echo "  status       - 查看 FutuOpenD 进程状态"
        echo "  log          - 查看最近 GTW 日志"
        echo "  enable-rsa   - 启用 RSA 加密（需重启容器生效）"
        echo "  disable-rsa  - 禁用 RSA 加密（需重启容器生效）"
        exit 1
        ;;
esac
