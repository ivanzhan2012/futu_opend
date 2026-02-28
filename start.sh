#!/bin/bash
set -e

# 创建必要的目录
mkdir -p /var/log/supervisor
mkdir -p /var/run/sshd

# 启动 supervisor
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisor_opend.conf &

# 等待 supervisor 启动
sleep 2

# 检查 supervisor 是否正常运行
if ! pgrep -x "supervisord" > /dev/null; then
    echo "Error: Supervisor failed to start"
    exit 1
fi

# 启动 SSHD 作为主进程
echo "Starting SSHD..."
exec /usr/sbin/sshd -D -f /etc/ssh/sshd_config