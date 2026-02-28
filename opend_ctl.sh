#!/bin/bash
# FutuOpenD 控制脚本
# 用法: opend_ctl.sh {start|stop|status|restart|log}

OPEND_CMD="/app/FutuOpenD/FutuOpenD"
OPEND_DIR="/app/FutuOpenD"
LOG_DIR="/var/log/supervisor"

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
}

log() {
    echo "=== 最近日志 (stdout) ==="
    tail -20 $LOG_DIR/opend.out.log 2>/dev/null || echo "无日志文件"
    echo ""
    echo "=== 最近日志 (stderr) ==="
    tail -20 $LOG_DIR/opend.err.log 2>/dev/null || echo "无日志文件"
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
    *)
        echo "用法: $0 {start|stop|status|restart|log}"
        echo ""
        echo "  start   - 启动 FutuOpenD"
        echo "  stop    - 停止 FutuOpenD"
        echo "  status  - 查看运行状态"
        echo "  restart - 重启 FutuOpenD"
        echo "  log     - 查看最近日志"
        exit 1
        ;;
esac
