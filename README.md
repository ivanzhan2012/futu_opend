# FutuOpenD Docker

富途 OpenD 服务的 Docker 容器化部署方案。

## 功能特性

- 富途 OpenD 服务容器化运行
- 支持 SSH 远程管理
- Supervisor 进程管理（可按需启用/禁用自动拉起）
- RSA 加密通信支持
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
| `FUTU_LOGIN_PWD` | 登录密码（明文或 32 位 MD5） | - |
| `FUTU_OPEND_PATH` | 宿主机上 OpenD 程序目录路径 | - |
| `FUTU_OPEND_IP` | OpenD 监听 IP | 0.0.0.0 |
| `FUTU_OPEND_PORT` | OpenD API 端口 | 11111 |
| `AUTO_HOLD_QUOTE_RIGHT` | 自动抢回高级行情权限（0/1） | 1 |
| `RSA_ENCRYPT_ENABLE` | 启用 RSA 加密通信（true/false） | false |
| `FUTU_PRIVATE_KEY` | 宿主机私钥文件路径（RSA 启用时生效） | - |
| `SSHD_PORT` | SSH 管理端口 | 34000 |
| `SSHD_IPADDR` | SSH 监听地址 | 0.0.0.0 |
| `ROOT_PASS` | SSH root 密码 | dzqBLfC7 |
| `CONTAINER_NAME` | 容器名称 | futu-opend |
| `IMAGE_NAME` | 镜像名称 | futu-opend |
| `IMAGE_TAG` | 镜像标签 | latest |
| `RESTART_POLICY` | Docker 重启策略 | unless-stopped |
| `NETWORK_NAME` | Docker 网络名称 | futu-network |

### 2. 准备私钥文件（可选）

如需启用 RSA 加密通信，将富途私钥文件放置为 `.futu_private_key.pem`，并在 `.env` 中设置：

```
RSA_ENCRYPT_ENABLE=true
FUTU_PRIVATE_KEY=./.futu_private_key.pem
```

### 3. 启动服务

推荐使用 `deploy_opend.sh` 脚本管理容器生命周期；也可直接使用原始的 docker-compose 命令。

#### 方式一：使用 deploy_opend.sh（推荐）

```bash
# 授予执行权限（首次）
chmod +x deploy_opend.sh

# 启动容器
./deploy_opend.sh start

# 首次登录（输入手机短信验证码完成设备认证）
./deploy_opend.sh first-login

# 启动 OpenD（首次登录完成后）
./deploy_opend.sh run
```

#### 方式二：原始 docker-compose 命令

```bash
# 构建并启动
docker-compose up -d --build

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down
```

## deploy_opend.sh 命令说明

```bash
./deploy_opend.sh [选项] <命令>

# 选项
-e, --env <file>    指定环境变量文件（默认: .env）
```

**容器命令**

| 命令 | 说明 |
|------|------|
| `start` | 启动容器 |
| `stop` | 停止容器 |
| `restart` | 重启容器 |
| `rebuild` | 重新构建镜像并启动容器 |
| `logs` | 查看容器日志 |
| `status` / `ps` | 查看容器状态 |
| `exec` | 进入容器 Shell |

**OpenD 命令**

| 命令 | 说明 |
|------|------|
| `first-login` | 首次登录（交互式输入短信验证码完成设备认证；已完成则直接显示状态） |
| `run` | 启动 OpenD（需先完成 `first-login`，通过 supervisor 管理） |
| `kill` | 停止 OpenD |
| `opend-logs` | 查看 OpenD 日志 |

**示例**

```bash
# 使用指定环境文件启动
./deploy_opend.sh -e .env.prod start

# 查看 OpenD 实时日志
./deploy_opend.sh opend-logs
```

## 首次使用流程

FutuOpenD 首次启动需要完成设备认证（输入手机短信验证码），因此容器默认 **不自动拉起 opend**，需手动完成认证后再启动。

**使用 deploy_opend.sh（推荐）**

```
第一次                              之后
──────────────────────────────────────────────────────────
./deploy_opend.sh start             ./deploy_opend.sh start
        ↓                                    ↓
./deploy_opend.sh first-login       ./deploy_opend.sh run
        ↓                           (supervisor 自动管理 OpenD)
输入短信验证码完成设备认证
        ↓
./deploy_opend.sh run
```

**使用原始 docker-compose**

```
第一次                          之后
─────────────────────────────────────────────────────
docker-compose up -d            docker-compose up -d
       ↓                               ↓
SSH 登入容器                    opend 由 supervisor 自动拉起
       ↓
手动运行 opend_ctl.sh start
       ↓
完成设备认证
       ↓
opend_ctl.sh enable-autostart   ← 设置完成后执行一次
```

## opend_ctl.sh 命令说明

容器内通过 `/app/opend_ctl.sh` 管理 opend：

```bash
/app/opend_ctl.sh <命令>
```

| 命令 | 说明 |
|------|------|
| `start` | 启动 FutuOpenD |
| `stop` | 停止 FutuOpenD |
| `restart` | 重启 FutuOpenD |
| `status` | 查看进程状态及 supervisor 自动拉起状态 |
| `log` | 查看最近日志（stdout + stderr） |
| `enable-rsa` | 启用 RSA 加密（注入私钥并重启） |
| `disable-rsa` | 禁用 RSA 加密（注释私钥并重启） |
| `enable-autostart` | **启用** supervisor 自动拉起（容器重启时自动启动 opend） |
| `disable-autostart` | **禁用** supervisor 自动拉起（排查问题时使用） |

### 自动拉起说明

- `enable-autostart`：修改容器内 supervisor 配置，下次容器重启时 opend 自动启动。设置完成后如需立即启动，再执行 `opend_ctl.sh start`。
- `disable-autostart`：关闭自动拉起，适合排查问题时防止 opend 被自动重启。
- `status`：会同时显示当前自动拉起是否启用。

> **注意**：自动拉起配置存储在容器内，重新创建容器（`docker-compose up -d --build` 或 `docker-compose down && up`）后需重新执行 `enable-autostart`。

## 端口说明

| 端口 | 用途 |
|------|------|
| 11111 | OpenD API 端口，供 SDK 连接 |
| 34000 | SSH 管理端口 |

## 文件结构

```
.
├── docker-compose.yml      # Docker Compose 配置
├── Dockerfile              # 镜像构建文件
├── deploy_opend.sh         # 部署管理脚本（推荐使用）
├── .env                    # 环境变量配置（不提交到版本控制）
├── .futu_private_key.pem   # 富途私钥（可选，不提交到版本控制）
├── start.sh                # 容器启动脚本
├── opend_ctl.sh            # OpenD 控制脚本（容器内使用）
├── supervisor_opend.conf   # Supervisor 配置（含 opend 程序定义）
├── supervisord.conf        # Supervisor 主配置
└── logs/                   # 日志目录
```

## 注意事项

1. 请妥善保管 `.env` 和私钥文件，不要提交到版本控制
2. 首次运行前请确保已从富途官方下载 OpenD 压缩包，并在 `.env` 中配置 `FUTU_OPEND_PATH`
3. 重新创建容器后需重新执行 `enable-autostart`（如有需要）
