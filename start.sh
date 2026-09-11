#!/bin/bash
set -e

OPEND_SRC="/opt/FutuOpenD_src"
OPEND_DIR="/app/FutuOpenD"
PRIVATE_KEY_SRC="/opt/.futu_private_key.pem"
PRIVATE_KEY_DST="$OPEND_DIR/.futu_private_key.pem"
XML_FILE="$OPEND_DIR/FutuOpenD.xml"

mkdir -p "$OPEND_DIR"

echo "[init] 复制 OpenD 文件到 $OPEND_DIR ..."
cp -a "$OPEND_SRC"/. "$OPEND_DIR"/

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

if [ ! -f "$XML_FILE" ]; then
    echo "Error: 未找到 $XML_FILE"
    exit 1
fi

echo "[init] 注入 XML 配置: account=$FUTU_LOGIN_ACCOUNT ip=$FUTU_OPEND_IP port=$FUTU_OPEND_PORT"

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

if [ ${#FUTU_LOGIN_PWD} -eq 32 ] && echo "$FUTU_LOGIN_PWD" | grep -qE '^[a-fA-F0-9]{32}$'; then
    sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<login_pwd_md5>${FUTU_LOGIN_PWD}</login_pwd_md5>|" "$XML_FILE"
    sed -i "s|<login_pwd>[^<]*</login_pwd>|<!-- <login_pwd>123456</login_pwd> -->|" "$XML_FILE"
else
    sed -i "s|<login_pwd>[^<]*</login_pwd>|<login_pwd>${FUTU_LOGIN_PWD}</login_pwd>|" "$XML_FILE"
    sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<!-- <login_pwd_md5>skipped</login_pwd_md5> -->|" "$XML_FILE"
fi

FUTU_TELNET_IP="${FUTU_TELNET_IP:-0.0.0.0}"
FUTU_TELNET_PORT="${FUTU_TELNET_PORT:-22222}"
echo "[init] 注入 telnet 配置: ip=$FUTU_TELNET_IP port=$FUTU_TELNET_PORT"
sed -i "s|<!-- <telnet_ip>[^<]*</telnet_ip> -->|<telnet_ip>${FUTU_TELNET_IP}</telnet_ip>|" "$XML_FILE"
sed -i "s|<!-- <telnet_port>[^<]*</telnet_port> -->|<telnet_port>${FUTU_TELNET_PORT}</telnet_port>|" "$XML_FILE"

mkdir -p /home/ubuntu/.com.futunn.FutuOpenD

chmod -R 755 "$OPEND_DIR"
chown -R ubuntu:ubuntu "$OPEND_DIR" /home/ubuntu/.com.futunn.FutuOpenD

echo "[init] 启动 FutuOpenD ..."

# 密码错误/账号锁定时 FutuOpenD 会快速退出(exit 14), 若无限重启会持续消耗
# 登录机会甚至触发账号锁定, 因此限制连续快速退出的重启次数
MAX_FAST_RESTARTS="${FUTU_MAX_FAST_RESTARTS:-3}"

term_handler() {
    kill -TERM "$opend_pid" 2>/dev/null || true
    wait "$opend_pid" 2>/dev/null || true
    exit 0
}
trap term_handler TERM INT

fast_restarts=0
while true; do
    start_ts=$(date +%s)
    runuser -u ubuntu -- "$OPEND_DIR/FutuOpenD" -no_monitor=1 &
    opend_pid=$!
    # 注意: start.sh 顶部有 set -e, 必须用 || 接住 wait 返回的 OpenD 非零退出码,
    # 否则脚本会直接退出, 退化为容器级无限重启(会持续消耗登录机会)
    rc=0
    wait "$opend_pid" || rc=$?
    end_ts=$(date +%s)
    runtime=$((end_ts - start_ts))

    # 账号锁定: 解析"请于今日 HH:MM 后重试", 睡到解锁后自动重试
    latest_gtw=$(ls -t /home/ubuntu/.com.futunn.FutuOpenD/Log/GTWLog_*.log 2>/dev/null | head -1 || true)
    if [ -n "$latest_gtw" ]; then
        unlock_hm=$(grep -aoE "请于今日 [0-9]{2}:[0-9]{2}" "$latest_gtw" 2>/dev/null | tail -1 | grep -aoE "[0-9]{2}:[0-9]{2}" || true)
        if [ -n "$unlock_hm" ]; then
            target_ts=$(date -d "today ${unlock_hm}" +%s || true)
            now_ts=$(date +%s)
            if [ -n "$target_ts" ]; then
                wait_s=$((target_ts - now_ts + 60))
                if [ "$wait_s" -gt 0 ] && [ "$wait_s" -le 21600 ]; then
                    echo "[start] 账号已锁定, ${unlock_hm} 解锁, 睡眠 ${wait_s}s 后自动重试登录"
                    sleep "$wait_s"
                    fast_restarts=0
                    continue
                fi
            fi
        fi
    fi

    if [ "$runtime" -lt 60 ]; then
        fast_restarts=$((fast_restarts + 1))
    else
        fast_restarts=0
    fi
    if [ "$fast_restarts" -ge "$MAX_FAST_RESTARTS" ]; then
        echo "[start] FutuOpenD 连续 ${fast_restarts} 次快速退出(退出码 ${rc}), 疑似密码错误或账号锁定, 停止重试"
        echo "[start] 容器将保持运行以便排查: docker compose logs futu-opend / 检查 .env 中 FUTU_LOGIN_PWD"
        exec tail -f /dev/null
    fi
    echo "[start] FutuOpenD 退出(码 ${rc}), ${runtime}s 后重启 (快速退出计数 ${fast_restarts}/${MAX_FAST_RESTARTS})"
    sleep 5
done
