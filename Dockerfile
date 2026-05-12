# syntax=docker/dockerfile:1
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

# 安装运行时依赖
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    tzdata \
    ca-certificates \
    curl \
    wget \
    vim \
    net-tools \
    iputils-ping \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# 构建期参数
ARG FUTU_OPEND_PORT=11111
ARG FUTU_OPEND_TELNET_PORT=22222
ARG FUTU_OPEND_DOWNLOAD_URL=https://softwaredownload.futunn.com/Futu_OpenD_10.5.6508_Ubuntu18.04.tar.gz
ARG FUTU_OPEND_PKG_NAME=Futu_OpenD_10.5.6508_Ubuntu18.04

ENV FUTU_OPEND_PORT=$FUTU_OPEND_PORT

# 创建非 root 用户 ubuntu，用于运行 FutuOpenD
RUN useradd -m -s /bin/bash ubuntu

# 创建必要目录
RUN mkdir -p /app/logs \
             /app/FutuOpenD \
             /opt/FutuOpenD_src \
             /home/ubuntu/.com.futunn.FutuOpenD && \
    chown -R ubuntu:ubuntu /app /home/ubuntu/.com.futunn.FutuOpenD

RUN --mount=type=bind,source=.,target=/build_ctx,rw=false \
    if [ -f "/build_ctx/${FUTU_OPEND_PKG_NAME}.tar.gz" ]; then \
        echo "[build] 使用本地离线包: ${FUTU_OPEND_PKG_NAME}.tar.gz" && \
        cp "/build_ctx/${FUTU_OPEND_PKG_NAME}.tar.gz" /tmp/opend.tar.gz; \
    else \
        echo "[build] 本地无离线包，从远程下载: ${FUTU_OPEND_DOWNLOAD_URL}" && \
        wget -q "${FUTU_OPEND_DOWNLOAD_URL}" -O /tmp/opend.tar.gz; \
    fi && \
    cd /tmp && \
    tar -xzf opend.tar.gz && \
    cp -a "${FUTU_OPEND_PKG_NAME}/${FUTU_OPEND_PKG_NAME}/." /opt/FutuOpenD_src/ && \
    rm -rf opend.tar.gz "${FUTU_OPEND_PKG_NAME}"

# 设置工作目录
WORKDIR /app

# 复制启动脚本
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 复制 opend 控制脚本
COPY opend_ctl.sh /app/opend_ctl.sh
RUN chmod +x /app/opend_ctl.sh

# 暴露端口
# FUTU_OPEND_PORT: OpenD API 端口，供 SDK 连接（默认 11111）
# FUTU_OPEND_TELNET_PORT: Telnet 管理端口，用于发送短信验证码（默认 22222）
# 注意：EXPOSE 仅作文档声明，实际端口映射由 docker-compose.yml 的 ports 字段控制
EXPOSE $FUTU_OPEND_PORT $FUTU_OPEND_TELNET_PORT

# 启动命令
CMD ["/app/start.sh"]
