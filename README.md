# FutuOpenD Docker

富途 OpenD 服务的 Docker 容器化部署方案。

## 功能特性

- 富途 OpenD 服务容器化运行
- 支持 SSH 远程管理
- Supervisor 进程管理
- 资源限制和健康检查

## 快速开始

### 1. 配置环境变量

复制并编辑 `.env` 文件：

```bash
cp .env.example .env
```

主要配置项：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `FUTU_LOGIN_ACCOUNT` | 富途登录账号 | - |
| `FUTU_LOGIN_PWD` | 登录密码或 MD5 值 | - |
| `FUTU_OPEND_PORT` | OpenD API 端口 | 11111 |
| `SSHD_PORT` | SSH 管理端口 | 34000 |
| `ROOT_PASS` | SSH root 密码 | dzqBLfC7 |

### 2. 准备私钥文件

将富途私钥文件放置为 `.futu_private_key.pem`

### 3. 启动服务

```bash
# 构建并启动
docker-compose up -d --build

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down
```

## 端口说明

| 端口 | 用途 |
|------|------|
| 11111 | OpenD API 端口，供 SDK 连接 |
| 34000 | SSH 管理端口 |

## 文件结构

```
.
├── docker-compose.yml    # Docker Compose 配置
├── Dockerfile            # 镜像构建文件
├── .env                  # 环境变量配置
├── .futu_private_key.pem # 富途私钥
├── start.sh              # 容器启动脚本
├── opend_ctl.sh          # OpenD 控制脚本
├── supervisor_opend.conf # Supervisor 配置
└── logs/                 # 日志目录
```

## 注意事项

1. 请妥善保管 `.env` 和私钥文件，不要提交到版本控制
2. 首次运行前请确保已从富途官方下载 OpenD 压缩包
