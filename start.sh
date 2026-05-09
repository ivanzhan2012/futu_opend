#!/bin/bash
set -e

OPEND_SRC="/opt/opend_src"
OPEND_DIR="/app/FutuOpenD"
PRIVATE_KEY_SRC="/opt/.futu_private_key.pem"
PRIVATE_KEY_DST="$OPEND_DIR/.futu_private_key.pem"
XML_FILE="$OPEND_DIR/FutuOpenD.xml"

# 创建必要的目录
mkdir -p /var/log/supervisor
mkdir -p /var/run/sshd
mkdir -p "$OPEND_DIR"

# 让 ubuntu 用户可以写 supervisor 日志
chown -R ubuntu:ubuntu /var/log/supervisor

# ---- 注入 SSH 公钥（可选）----
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    echo "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[init] SSH 公钥已注入 (/root/.ssh/authorized_keys)"
else
    echo "[init] SSH_AUTHORIZED_KEYS 未设置，跳过公钥注入（可用 docker exec 进入容器）"
fi

# ---- 从挂载的只读源目录复制 OpenD 文件到容器内可写目录 ----
if [ ! -d "$OPEND_SRC" ] || [ -z "$(ls -A "$OPEND_SRC" 2>/dev/null)" ]; then
    echo "Error: OpenD source not mounted at $OPEND_SRC. 请在 .env 中配置 FUTU_OPEND_PATH。"
    exit 1
fi

echo "[init] 复制 OpenD 文件到 $OPEND_DIR ..."
# -a 保留权限/链接；尾部的 /. 保证复制目录内容而非目录本身
cp -a "$OPEND_SRC"/. "$OPEND_DIR"/

# ---- 复制私钥（受 RSA_ENCRYPT_ENABLE 控制）----
RSA_ENCRYPT_ENABLE="${RSA_ENCRYPT_ENABLE:-false}"
if [ "$RSA_ENCRYPT_ENABLE" = "true" ] || [ "$RSA_ENCRYPT_ENABLE" = "1" ]; then
    if [ -f "$PRIVATE_KEY_SRC" ]; then
        echo "[init] 复制私钥 ..."
        cp "$PRIVATE_KEY_SRC" "$PRIVATE_KEY_DST"
        chmod 600 "$PRIVATE_KEY_DST"
        chown ubuntu:ubuntu "$PRIVATE_KEY_DST"
    else
        echo "[warn] RSA_ENCRYPT_ENABLE=true 但未找到私钥 $PRIVATE_KEY_SRC，将跳过 rsa_private_key 配置"
    fi
else
    echo "[init] RSA_ENCRYPT_ENABLE=false，跳过私钥配置"
fi

# ---- 注入 XML 配置 ----
if [ ! -f "$XML_FILE" ]; then
    echo "Error: 未找到 $XML_FILE"
    exit 1
fi

echo "[init] 注入 XML 配置: account=$FUTU_LOGIN_ACCOUNT ip=$FUTU_OPEND_IP port=$FUTU_OPEND_PORT auto_hold=$AUTO_HOLD_QUOTE_RIGHT"

sed -i "s|<login_account>[^<]*</login_account>|<login_account>${FUTU_LOGIN_ACCOUNT}</login_account>|" "$XML_FILE"
sed -i "s|<ip>[^<]*</ip>|<ip>${FUTU_OPEND_IP}</ip>|" "$XML_FILE"
sed -i "s|<api_port>[^<]*</api_port>|<api_port>${FUTU_OPEND_PORT}</api_port>|" "$XML_FILE"
sed -i "s|<auto_hold_quote_right>[^<]*</auto_hold_quote_right>|<auto_hold_quote_right>${AUTO_HOLD_QUOTE_RIGHT}</auto_hold_quote_right>|" "$XML_FILE"

if [ "$RSA_ENCRYPT_ENABLE" = "true" ] || [ "$RSA_ENCRYPT_ENABLE" = "1" ]; then
    if [ -f "$PRIVATE_KEY_DST" ]; then
        echo "[init] 注入 RSA 私钥配置 ..."
        sed -i "s|<!-- <rsa_private_key>[^<]*</rsa_private_key> -->|<rsa_private_key>${PRIVATE_KEY_DST}</rsa_private_key>|" "$XML_FILE"
    fi
fi

# 登录密码：32位十六进制 => 用 login_pwd_md5；否则用明文 login_pwd
if [ ${#FUTU_LOGIN_PWD} -eq 32 ] && echo "$FUTU_LOGIN_PWD" | grep -qE '^[a-fA-F0-9]{32}$'; then
    sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<login_pwd_md5>${FUTU_LOGIN_PWD}</login_pwd_md5>|" "$XML_FILE"
    sed -i "s|<login_pwd>[^<]*</login_pwd>|<!-- <login_pwd>123456</login_pwd> -->|" "$XML_FILE"
else
    sed -i "s|<login_pwd>[^<]*</login_pwd>|<login_pwd>${FUTU_LOGIN_PWD}</login_pwd>|" "$XML_FILE"
    sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<!-- <login_pwd_md5>skipped</login_pwd_md5> -->|" "$XML_FILE"
fi

# 确保 OpenD 数据目录存在
mkdir -p /home/ubuntu/.com.futunn.FutuOpenD

chmod -R 755 "$OPEND_DIR"

# 将 OpenD 运行目录和数据目录归属 ubuntu 用户
chown -R ubuntu:ubuntu "$OPEND_DIR" /home/ubuntu/.com.futunn.FutuOpenD

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
