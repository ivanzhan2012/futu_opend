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
exec runuser -u ubuntu -- "$OPEND_DIR/FutuOpenD" -no_monitor=1
