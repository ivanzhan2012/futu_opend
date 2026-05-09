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

# 安装运行时依赖（网络检查 + 排障 + 核心服务）
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    wget \
    vim \
    net-tools \
    iputils-ping \
    netcat-traditional \
    openssh-server \
    supervisor \
    screen \
    && rm -rf /var/lib/apt/lists/*


# 构建期参数（仅 SSH 相关需要在构建时写入镜像）
ARG SSHD_IPADDR=0.0.0.0
ARG SSHD_PORT=34000
ARG ROOT_PASS=opend@kline
ARG FUTU_OPEND_PORT=11111

ENV SSHD_IPADDR=$SSHD_IPADDR
ENV SSHD_PORT=$SSHD_PORT
ENV ROOT_PASS=$ROOT_PASS
ENV FUTU_OPEND_PORT=$FUTU_OPEND_PORT

# 配置 SSH
RUN mkdir -p /var/run/sshd
RUN echo "root:$ROOT_PASS"| chpasswd
RUN sed -i "s/#Port 22/Port $SSHD_PORT/" /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i "s/#ListenAddress 0.0.0.0/ListenAddress $SSHD_IPADDR/" /etc/ssh/sshd_config

# 创建必要的目录
RUN mkdir -p /var/log/supervisor && \
    mkdir -p /var/run/sshd && \
    mkdir -p /app/logs && \
    mkdir -p /app/FutuOpenD

# 配置 supervisor
RUN mkdir -p /etc/supervisor/conf.d
COPY supervisor_opend.conf /etc/supervisor/conf.d/

# 设置工作目录
WORKDIR /app

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
