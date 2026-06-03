#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE=".env"

load_env() {
    local env_path="$1"
    if [[ "$env_path" != /* ]]; then
        env_path="$SCRIPT_DIR/$env_path"
    fi
    if [ -f "$env_path" ]; then
        echo -e "${BLUE}[INFO]${NC} 加载环境变量: $env_path"
        set -a
        source <(grep -v '^#' "$env_path" | grep -v '^$')
        set +a
    else
        echo -e "${RED}[ERROR]${NC} 环境变量文件不存在: $env_path"
        exit 1
    fi
}

COMPOSE_SERVICE="futu-opend"

ensure_network() {
    local network_name="${NETWORK_NAME:-futu-network}"
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        echo -e "${GREEN}[NETWORK]${NC} 网络 ${network_name} 已存在"
    else
        echo -e "${BLUE}[NETWORK]${NC} 创建网络: ${network_name}"
        docker network create --driver bridge "${network_name}"
        echo -e "${GREEN}[NETWORK]${NC} 网络 ${network_name} 创建成功"
    fi
}

compose_exec() {
    docker-compose exec -T "${COMPOSE_SERVICE}" "$@"
}

compose_exec_interactive() {
    docker-compose exec "${COMPOSE_SERVICE}" "$@"
}

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
    echo "  first-login                          首次登录（检测到需要短信验证时，交互式输入验证码）"
    echo "  input_phone_verify_code -code=XXXXXX 直接发送短信验证码"
    echo "  opend-logs                           查看 OpenD 日志"
    echo ""
    echo "标准流程:"
    echo "  1. $0 start                                    # 启动容器"
    echo "  2. $0 first-login                              # 等待提示后输入验证码"
    echo "  或 $0 input_phone_verify_code -code=123456     # 直接发送验证码"
    echo ""
}

start_service() {
    echo -e "${GREEN}[START]${NC} 启动容器..."
    ensure_network
    echo -e "${BLUE}[INFO]${NC} 端口映射: OpenD=${FUTU_OPEND_PORT:-11111}, Telnet=${FUTU_TELNET_PORT:-22222}"
    docker-compose up -d
    echo -e "${GREEN}[DONE]${NC} 容器已启动"
    echo -e "${YELLOW}[TIP]${NC} 如需首次短信验证，执行: '$0 first-login'"
    show_status
}

stop_service() {
    echo -e "${YELLOW}[STOP]${NC} 停止容器..."
    docker-compose down
    echo -e "${GREEN}[DONE]${NC} 容器已停止"
}

restart_service() {
    echo -e "${YELLOW}[RESTART]${NC} 重启容器..."
    docker-compose restart
    echo -e "${GREEN}[DONE]${NC} 容器已重启"
    show_status
}

rebuild_service() {
    local build_args=""
    if [ "${NO_CACHE:-false}" = "true" ]; then
        build_args="--no-cache"
        echo -e "${BLUE}[BUILD]${NC} 重新构建镜像（无缓存，将重新下载 OpenD）..."
    else
        echo -e "${BLUE}[BUILD]${NC} 重新构建镜像..."
    fi
    ensure_network
    docker-compose build $build_args
    echo -e "${GREEN}[START]${NC} 启动容器..."
    docker-compose up -d --force-recreate
    echo -e "${GREEN}[DONE]${NC} 容器已重建并启动"
    echo -e "${YELLOW}[TIP]${NC} 如需首次短信验证，执行: '$0 first-login'"
    show_status
}

show_logs() {
    echo -e "${BLUE}[LOGS]${NC} 查看容器日志 (Ctrl+C 退出)..."
    docker-compose logs -f --tail=100
}

show_status() {
    echo -e "${BLUE}[STATUS]${NC} 容器状态:"
    docker-compose ps
    echo ""
    echo -e "${BLUE}[INFO]${NC} OpenD 进程:"
    compose_exec pgrep -x FutuOpenD > /dev/null 2>&1 && \
        echo "OpenD 运行中" || echo "OpenD 未运行"
}

exec_container() {
    echo -e "${BLUE}[EXEC]${NC} 进入容器..."
    compose_exec_interactive /bin/bash
}

is_first_login_done() {
    local log_dir="/home/ubuntu/.com.futunn.FutuOpenD/Log"
    local latest_gtw
    latest_gtw=$(compose_exec \
        sh -c "ls -t ${log_dir}/GTWLog_*.log 2>/dev/null | head -1")
    [ -z "$latest_gtw" ] && return 1
    if compose_exec grep -q 'req_phone_verify_code' "$latest_gtw" 2>/dev/null; then
        return 1
    fi
    compose_exec grep -q 'ProgramStatusType_Ready' "$latest_gtw" 2>/dev/null
}

needs_phone_verify() {
    local log_dir="/home/ubuntu/.com.futunn.FutuOpenD/Log"
    local latest_gtw
    latest_gtw=$(compose_exec \
        sh -c "ls -t ${log_dir}/GTWLog_*.log 2>/dev/null | head -1")
    [ -z "$latest_gtw" ] && return 1
    compose_exec grep -q 'req_phone_verify_code' "$latest_gtw" 2>/dev/null
}

send_verify_code() {
    local code="$1"
    local telnet_port="${FUTU_TELNET_PORT:-22222}"
    if [ -z "$code" ]; then
        echo -e "${RED}[ERROR]${NC} 验证码不能为空"
        exit 1
    fi
    echo -e "${BLUE}[VERIFY]${NC} 发送验证码到容器 telnet_port=$telnet_port ..."
    printf "input_phone_verify_code -code=${code}\r\n" | \
        compose_exec nc -q 2 127.0.0.1 "$telnet_port"
    echo ""
    echo -e "${GREEN}[DONE]${NC} 验证码已发送，等待 OpenD 验证..."
    sleep 3
    if is_first_login_done; then
        echo -e "${GREEN}[OK]${NC} 登录成功！"
    else
        echo -e "${YELLOW}[WARN]${NC} 未检测到登录成功日志，请查看日志: $0 opend-logs"
    fi
}

first_login_opend() {
    if ! compose_exec true 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} 容器未运行，请先执行: $0 start"
        exit 1
    fi

    if is_first_login_done; then
        echo -e "${GREEN}[FIRST-LOGIN]${NC} 首次登录已完成，无需重复操作"
        return 0
    fi

    echo -e "${BLUE}[FIRST-LOGIN]${NC} 等待 OpenD 启动并检测短信验证需求..."

    local waited=0
    local max_wait=30
    while [ $waited -lt $max_wait ]; do
        if needs_phone_verify; then
            break
        fi
        if is_first_login_done; then
            echo -e "${GREEN}[FIRST-LOGIN]${NC} OpenD 已自动登录成功，无需短信验证"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo -e "${BLUE}[FIRST-LOGIN]${NC} 等待中... (${waited}s)"
    done

    if ! needs_phone_verify && ! is_first_login_done; then
        echo -e "${YELLOW}[WARN]${NC} 超时未检测到验证码请求，请查看日志: $0 opend-logs"
        echo -e "${YELLOW}[TIP]${NC} 如果确实需要验证码，请手动执行: $0 input_phone_verify_code -code=XXXXXX"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}[FIRST-LOGIN]${NC} OpenD 需要短信验证码，请查收手机短信"
    printf "请输入验证码: "
    read -r code
    if [ -z "$code" ]; then
        echo -e "${RED}[ERROR]${NC} 验证码不能为空"
        exit 1
    fi
    send_verify_code "$code"
}

show_opend_logs() {
    echo -e "${BLUE}[LOGS]${NC} 查看 OpenD 日志 (Ctrl+C 退出)..."
    compose_exec_interactive \
        sh -c 'tail -f $(ls -t /home/ubuntu/.com.futunn.FutuOpenD/Log/GTWLog_*.log 2>/dev/null | head -1) 2>/dev/null || echo "暂无日志文件"'
}

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
            input_phone_verify_code)
                COMMAND="input_phone_verify_code"
                shift
                VERIFY_CODE_ARG="$*"
                break
                ;;
            start|stop|restart|rebuild|logs|status|ps|exec|first-login|opend-logs)
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

parse_options "$@"
load_env "$ENV_FILE"

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
    input_phone_verify_code)
        code=$(echo "$VERIFY_CODE_ARG" | sed 's/.*-code=\([^ ]*\).*/\1/')
        send_verify_code "$code"
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
