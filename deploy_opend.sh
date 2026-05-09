#!/bin/bash
# ===========================================
# FutuOpenD Docker 部署/重启脚本
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 默认环境变量文件
ENV_FILE=".env"

# 加载环境变量
load_env() {
    local env_path="$1"

    # 如果是相对路径，转换为绝对路径
    if [[ "$env_path" != /* ]]; then
        env_path="$SCRIPT_DIR/$env_path"
    fi

    if [ -f "$env_path" ]; then
        echo -e "${BLUE}[INFO]${NC} 加载环境变量: $env_path"
        # 安全地导出环境变量，处理包含特殊字符的值
        set -a
        source <(grep -v '^#' "$env_path" | grep -v '^$')
        set +a
    else
        echo -e "${RED}[ERROR]${NC} 环境变量文件不存在: $env_path"
        exit 1
    fi
}

# 确保 Docker 网络存在
ensure_network() {
    local network_name="${NETWORK_NAME:-futu-network}"

    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        echo -e "${GREEN}[NETWORK]${NC} 网络 ${network_name} 已存在，将使用现有网络"
    else
        echo -e "${BLUE}[NETWORK]${NC} 创建网络: ${network_name}"
        docker network create --driver bridge "${network_name}"
        echo -e "${GREEN}[NETWORK]${NC} 网络 ${network_name} 创建成功"
    fi
}

# 帮助信息
show_help() {
    echo -e "${BLUE}FutuOpenD Docker 部署脚本${NC}"
    echo ""
    echo "用法: $0 [选项] [命令]"
    echo ""
    echo "选项:"
    echo "  -e, --env <file>    指定环境变量文件 (默认: .env)"
    echo ""
    echo "容器命令:"
    echo "  start       启动容器"
    echo "  stop        停止容器"
    echo "  restart     重启容器"
    echo "  rebuild     重新构建并启动容器"
    echo "  logs        查看容器日志"
    echo "  status      查看容器状态"
    echo "  ps          查看容器状态"
    echo "  exec        进入容器"
    echo ""
    echo "OpenD 命令:"
    echo "  first-login 首次登录（若已完成则显示状态；若未完成则交互式输入短信验证码）"
    echo "  run         启动 OpenD（需先完成 first-login，通过 supervisor 管理）"
    echo "  kill        停止 OpenD"
    echo "  opend-logs  查看 OpenD 日志"
    echo ""
    echo "标准流程:"
    echo "  1. $0 start                   # 启动容器"
    echo "  2. $0 first-login             # 首次登录（输入短信验证码）"
    echo "  3. $0 run                     # 启动 OpenD（首次登录完成后）"
    echo ""
    echo "其他示例:"
    echo "  $0 -e .env.prod start         # 使用 .env.prod 启动容器"
    echo ""
}

# 启动容器
start_service() {
    echo -e "${GREEN}[START]${NC} 启动容器..."
    ensure_network
    echo -e "${BLUE}[INFO]${NC} 端口映射: OpenD=${FUTU_OPEND_PORT:-11111}, SSH=${SSHD_PORT:-34000}"
    docker-compose up -d
    echo -e "${GREEN}[DONE]${NC} 容器已启动"
    echo -e "${YELLOW}[TIP]${NC} 下一步: '$0 first-login' 完成首次登录，再执行 '$0 run' 启动 OpenD"
    show_status
}

# 停止容器
stop_service() {
    echo -e "${YELLOW}[STOP]${NC} 停止容器..."
    docker-compose down
    echo -e "${GREEN}[DONE]${NC} 容器已停止"
}

# 重启容器
restart_service() {
    echo -e "${YELLOW}[RESTART]${NC} 重启容器..."
    docker-compose restart
    echo -e "${GREEN}[DONE]${NC} 容器已重启"
    show_status
}

# 重新构建
rebuild_service() {
    echo -e "${BLUE}[BUILD]${NC} 重新构建镜像..."
    ensure_network
    docker-compose build --no-cache
    echo -e "${GREEN}[START]${NC} 启动容器..."
    docker-compose up -d --force-recreate
    echo -e "${GREEN}[DONE]${NC} 容器已重建并启动"
    echo -e "${YELLOW}[TIP]${NC} 下一步: '$0 first-login' 完成首次登录，再执行 '$0 run' 启动 OpenD"
    show_status
}

# 查看日志
show_logs() {
    echo -e "${BLUE}[LOGS]${NC} 查看容器日志 (Ctrl+C 退出)..."
    docker-compose logs -f --tail=100
}

# 查看状态
show_status() {
    echo -e "${BLUE}[STATUS]${NC} 容器状态:"
    docker-compose ps
    echo ""
    echo -e "${BLUE}[INFO]${NC} OpenD 进程:"
    docker exec ${CONTAINER_NAME:-futu-opend} pgrep -x FutuOpenD > /dev/null 2>&1 && \
        echo "OpenD 运行中" || echo "OpenD 未运行"
}

# 进入容器
exec_container() {
    echo -e "${BLUE}[EXEC]${NC} 进入容器..."
    docker exec -it ${CONTAINER_NAME:-futu-opend} /bin/bash
}

# 检查首次登录是否已完成
# Device.dat 不可靠（登录失败也会生成），改用 GTW 日志判断：
# 取最近一个 GTW 日志，如果出现 req_phone_verify_code 说明需要短信验证（首次登录未完成）
# 如果出现 ProgramStatusType_Ready 说明登录成功
is_first_login_done() {
    local log_dir="/home/ubuntu/.com.futunn.FutuOpenD/Log"
    local latest_gtw

    latest_gtw=$(docker exec ${CONTAINER_NAME:-futu-opend} \
        sh -c "ls -t ${log_dir}/GTWLog_*.log 2>/dev/null | head -1")

    [ -z "$latest_gtw" ] && return 1

    # 最近日志需要短信验证 → 首次登录未完成
    if docker exec ${CONTAINER_NAME:-futu-opend} grep -q 'req_phone_verify_code' "$latest_gtw" 2>/dev/null; then
        return 1
    fi

    # 最近日志有 Ready 状态 → 登录成功
    docker exec ${CONTAINER_NAME:-futu-opend} grep -q 'ProgramStatusType_Ready' "$latest_gtw" 2>/dev/null
}

# 显示容器内 OpenD 进程状态
show_opend_status() {
    echo -e "${BLUE}[OPEND STATUS]${NC}"
    local running
    running=$(docker exec ${CONTAINER_NAME:-futu-opend} pgrep -x FutuOpenD 2>/dev/null || true)
    if [ -n "$running" ]; then
        echo -e "  FutuOpenD 进程: ${GREEN}运行中${NC} (PID: $running)"
    else
        echo -e "  FutuOpenD 进程: ${YELLOW}未运行${NC}"
        echo -e "  ${YELLOW}[TIP]${NC} 使用 '$0 run' 启动 OpenD"
    fi
    echo ""
    echo -e "${BLUE}[SUPERVISOR STATUS]${NC}"
    docker exec ${CONTAINER_NAME:-futu-opend} supervisorctl status opend 2>/dev/null || true
}

# 首次登录 (交互式前台运行，输入短信验证码)
first_login_opend() {
    # 检查容器是否运行
    if ! docker exec ${CONTAINER_NAME:-futu-opend} true 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} 容器未运行，请先执行: $0 start"
        exit 1
    fi

    # 已完成首次登录则直接显示状态
    if is_first_login_done; then
        echo -e "${GREEN}[FIRST-LOGIN]${NC} 首次登录已完成，无需重复操作"
        echo -e "${BLUE}[INFO]${NC} GTW 日志显示此前已成功登录，OpenD 可直接启动"
        echo ""
        show_opend_status
        return 0
    fi

    echo -e "${GREEN}[FIRST-LOGIN]${NC} 进入首次登录交互模式..."
    echo -e "${YELLOW}[TIP]${NC} FutuOpenD 将在容器内以前台模式运行，请按提示输入短信验证码"
    echo -e "${YELLOW}[TIP]${NC} 登录成功后，按 Ctrl+C 或等待退出，然后使用 '$0 run' 正常启动"
    echo ""
    docker exec -it ${CONTAINER_NAME:-futu-opend} /app/opend_ctl.sh first-login

    # 交互式登录结束后，自动验证是否真正成功
    echo ""
    if is_first_login_done; then
        echo -e "${GREEN}[FIRST-LOGIN]${NC} 验证通过！GTW 日志确认登录成功"
        echo -e "${YELLOW}[TIP]${NC} 下一步: '$0 run' 启动 OpenD"
    else
        echo -e "${RED}[FIRST-LOGIN]${NC} 验证失败：GTW 日志未检测到成功登录记录"
        echo -e "${YELLOW}[TIP]${NC} 请重新执行 '$0 first-login' 完成短信验证"
    fi
}

# 启动 OpenD（通过 supervisor 管理）
run_opend() {
    # 检查容器是否运行
    if ! docker exec ${CONTAINER_NAME:-futu-opend} true 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} 容器未运行，请先执行: $0 start"
        exit 1
    fi

    # 未完成首次登录则阻止启动
    if ! is_first_login_done; then
        echo -e "${RED}[ERROR]${NC} 首次登录未完成，无法启动 OpenD"
        echo -e "${YELLOW}[TIP]${NC} 请先执行: $0 first-login"
        echo -e "${YELLOW}[TIP]${NC} 按提示输入手机短信验证码完成首次登录"
        exit 1
    fi

    echo -e "${GREEN}[RUN]${NC} 首次登录已完成，通过 supervisor 启动 OpenD..."
    docker exec ${CONTAINER_NAME:-futu-opend} supervisorctl start opend
    echo ""
    echo -e "${BLUE}[INFO]${NC} 查看 OpenD 日志: $0 opend-logs"
}

# 停止 OpenD
kill_opend() {
    echo -e "${YELLOW}[KILL]${NC} 停止 OpenD..."
    docker exec ${CONTAINER_NAME:-futu-opend} supervisorctl stop opend
    echo -e "${GREEN}[DONE]${NC} OpenD 已停止"
}

# 查看 OpenD 日志
show_opend_logs() {
    echo -e "${BLUE}[LOGS]${NC} 查看 OpenD 日志 (Ctrl+C 退出)..."
    docker exec -it ${CONTAINER_NAME:-futu-opend} tail -f /var/log/supervisor/opend.out.log /var/log/supervisor/opend.err.log 2>/dev/null
}

# 解析选项
parse_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                if [ -z "$2" ]; then
                    echo -e "${RED}[ERROR]${NC} --env 需要指定文件路径"
                    exit 1
                fi
                ENV_FILE="$2"
                shift 2
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            start|stop|restart|rebuild|logs|status|ps|exec|first-login|run|kill|opend-logs)
                COMMAND="$1"
                shift
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} 未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 主逻辑
parse_options "$@"

# 加载环境变量
load_env "$ENV_FILE"

# 执行命令
case "${COMMAND:-help}" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    rebuild)
        rebuild_service
        ;;
    logs)
        show_logs
        ;;
    status|ps)
        show_status
        ;;
    exec)
        exec_container
        ;;
    first-login)
        first_login_opend
        ;;
    run)
        run_opend
        ;;
    kill)
        kill_opend
        ;;
    opend-logs)
        show_opend_logs
        ;;
    help)
        show_help
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 未知命令: $COMMAND"
        show_help
        exit 1
        ;;
esac
