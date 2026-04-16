FROM ubuntu:22.04

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 配置阿里云源
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list.d/aliyun.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list.d/aliyun.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list.d/aliyun.list

# 安装基础工具和依赖
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y --fix-missing \
    build-essential \
    pkg-config \
    git \
    curl \
    wget \
    vim \
    net-tools \
    iputils-ping \
    libssl-dev \
    libffi-dev \
    libsqlite3-dev \
    libreadline-dev \
    libbz2-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    default-libmysqlclient-dev \
    sudo \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip \
    netcat-traditional \
    openssh-server \
    supervisor \
    screen \
    && rm -rf /var/lib/apt/lists/*


# 设置构建参数
ARG SSHD_IPADDR=0.0.0.0
ARG SSHD_PORT=34000
ARG ROOT_PASS=opend@kline
ARG FUTU_LOGIN_ACCOUNT=275150
ARG FUTU_LOGIN_PWD=123456
ARG FUTU_OPEND_IP=0.0.0.0
ARG FUTU_OPEND_PORT=11111
ARG AUTO_HOLD_QUOTE_RIGHT=0

# 设置环境变量
ENV SSHD_IPADDR=$SSHD_IPADDR
ENV SSHD_PORT=$SSHD_PORT
ENV ROOT_PASS=$ROOT_PASS
ENV FUTU_LOGIN_ACCOUNT=$FUTU_LOGIN_ACCOUNT
ENV FUTU_LOGIN_PWD=$FUTU_LOGIN_PWD
ENV FUTU_OPEND_IP=$FUTU_OPEND_IP
ENV FUTU_OPEND_PORT=$FUTU_OPEND_PORT
ENV AUTO_HOLD_QUOTE_RIGHT=$AUTO_HOLD_QUOTE_RIGHT

# 配置 SSH
RUN mkdir -p /var/run/sshd
RUN echo "root:$ROOT_PASS"| chpasswd
RUN sed -i "s/#Port 22/Port $SSHD_PORT/" /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i "s/#ListenAddress 0.0.0.0/ListenAddress $SSHD_IPADDR/" /etc/ssh/sshd_config

# 创建必要的目录
RUN mkdir -p /var/log/supervisor && \
    mkdir -p /var/run/sshd && \
    mkdir -p /app/logs

# 配置 supervisor
RUN mkdir -p /etc/supervisor/conf.d
COPY supervisor_opend.conf /etc/supervisor/conf.d/

# 设置工作目录
WORKDIR /app

# 复制 FutuOpenD
COPY Futu_OpenD_9.6.5618_Ubuntu18.04 /app/FutuOpenD

# 复制私钥
COPY .futu_private_key.pem /app/FutuOpenD/.futu_private_key.pem

# 修改 FutuOpenD 配置文件
# 注意：原始 XML 中 <login_pwd_md5> 和 <rsa_private_key> 是被注释的，需要特殊处理
# 如果 FUTU_LOGIN_PWD 是 32 位十六进制，使用 login_pwd_md5；否则使用 login_pwd
RUN sed -i "s/<login_account>[^<]*<\/login_account>/<login_account>$FUTU_LOGIN_ACCOUNT<\/login_account>/" /app/FutuOpenD/FutuOpenD.xml && \
    sed -i "s/<ip>[^<]*<\/ip>/<ip>$FUTU_OPEND_IP<\/ip>/" /app/FutuOpenD/FutuOpenD.xml && \
    sed -i "s/<api_port>[^<]*<\/api_port>/<api_port>$FUTU_OPEND_PORT<\/api_port>/" /app/FutuOpenD/FutuOpenD.xml && \
    sed -i "s/<auto_hold_quote_right>[^<]*<\/auto_hold_quote_right>/<auto_hold_quote_right>$AUTO_HOLD_QUOTE_RIGHT<\/auto_hold_quote_right>/" /app/FutuOpenD/FutuOpenD.xml && \
    sed -i "s|<!-- <rsa_private_key>[^<]*</rsa_private_key> -->|<rsa_private_key>/app/FutuOpenD/.futu_private_key.pem</rsa_private_key>|" /app/FutuOpenD/FutuOpenD.xml && \
    if [ ${#FUTU_LOGIN_PWD} -eq 32 ] && echo "$FUTU_LOGIN_PWD" | grep -qE '^[a-fA-F0-9]{32}$'; then \
        sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<login_pwd_md5>$FUTU_LOGIN_PWD</login_pwd_md5>|" /app/FutuOpenD/FutuOpenD.xml && \
        sed -i "s|<login_pwd>[^<]*</login_pwd>|<!-- <login_pwd>123456</login_pwd> -->|" /app/FutuOpenD/FutuOpenD.xml; \
    else \
        sed -i "s|<login_pwd>[^<]*</login_pwd>|<login_pwd>$FUTU_LOGIN_PWD</login_pwd>|" /app/FutuOpenD/FutuOpenD.xml && \
        sed -i "s|<!-- <login_pwd_md5>[^<]*</login_pwd_md5> -->|<!-- <login_pwd_md5>skipped</login_pwd_md5> -->|" /app/FutuOpenD/FutuOpenD.xml; \
    fi

# 设置权限
RUN chmod -R 755 /app/FutuOpenD

# 复制启动脚本
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 复制 opend 控制脚本
COPY opend_ctl.sh /app/opend_ctl.sh
RUN chmod +x /app/opend_ctl.sh

# 暴露端口
EXPOSE $SSHD_PORT
EXPOSE $FUTU_OPEND_PORT

# 启动命令
CMD ["/app/start.sh"]
