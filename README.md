# FutuOpenD Docker

富途 OpenD 服务的 Docker 容器化部署方案。

## 功能特性

- 富途 OpenD 服务容器化运行
- 构建时优先使用本地离线安装包，无本地包时自动从官方下载
- 通过 telnet_port 发送短信验证码完成首次登录（无需 SSH）
- RSA 加密通信支持
- 资源限制和健康检查

## 快速开始

### 1. 配置环境变量

复制并编辑 `.env` 文件：

```bash
cp .env.example .env
```

编辑 `FUTU_LOGIN_ACCOUNT` 和 `FUTU_LOGIN_PWD`，其中密码需要使用 MD5 格式：

```bash
# 生成密码 MD5（交互式输入，不会回显明文）
python3 generate_futu_pwd_md5.py

# 或直接传入密码参数
python3 generate_futu_pwd_md5.py 你的密码
```

将生成的 32 位 MD5 值填入 `.env` 的 `FUTU_LOGIN_PWD` 字段。

主要配置项：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `FUTU_LOGIN_ACCOUNT` | 富途登录账号 | - |
| `FUTU_LOGIN_PWD` | 登录密码（32 位 MD5，通过 `generate_futu_pwd_md5.py` 生成） | - |
| `FUTU_OPEND_IP` | OpenD 监听 IP | 0.0.0.0 |
| `FUTU_OPEND_PORT` | OpenD API 端口 | 11111 |
| `FUTU_TELNET_IP` | Telnet 监听 IP | 0.0.0.0 |
| `FUTU_TELNET_PORT` | Telnet 端口（用于发送短信验证码） | 22222 |
| `AUTO_HOLD_QUOTE_RIGHT` | 自动抢回高级行情权限（0/1） | 1 |
| `RSA_ENCRYPT_ENABLE` | 启用 RSA 加密通信（true/false） | false |
| `FUTU_PRIVATE_KEY` | 宿主机私钥文件路径（RSA 启用时生效） | - |
| `CONTAINER_NAME` | 容器名称 | futu-opend |
| `IMAGE_NAME` | 镜像名称 | futu-opend |
| `IMAGE_TAG` | 镜像标签 | latest |
| `RESTART_POLICY` | Docker 重启策略 | unless-stopped |
| `NETWORK_NAME` | Docker 网络名称 | futu-network |
| `FUTU_OPEND_DOWNLOAD_URL` | OpenD 下载地址 | 官方 Ubuntu 18.04 版本 |
| `FUTU_OPEND_PKG_NAME` | 下载包名（用于解压路径） | Futu_OpenD_10.5.6508_Ubuntu18.04 |

### 2. 构建并启动

```bash
chmod +x deploy_opend.sh

# 首次构建（会自动下载 OpenD，约需几分钟）
./deploy_opend.sh rebuild

# 之后直接启动
./deploy_opend.sh start
```

> **网络不稳定？使用本地离线包构建**
>
> 将对应版本的 `.tar.gz` 放到项目根目录，构建时会自动优先使用本地文件，无需网络下载：
>
> ```bash
> # 将安装包放到项目根目录（文件名须与 FUTU_OPEND_PKG_NAME 匹配）
> ls Futu_OpenD_10.5.6508_Ubuntu18.04.tar.gz
>
> # 正常执行 rebuild，构建时自动检测并使用本地包
> ./deploy_opend.sh rebuild
> ```

### 3. 首次短信验证

FutuOpenD 首次启动需要短信验证码完成设备认证：

```bash
# 方式一：交互式（自动等待验证码提示后输入）
./deploy_opend.sh first-login

# 方式二：直接发送验证码
./deploy_opend.sh input_phone_verify_code -code=123456
```

## 使用流程

```
第一次                                  之后
────────────────────────────────────────────────────────────
./deploy_opend.sh rebuild               ./deploy_opend.sh start
        ↓                               (容器重启后 OpenD 自动运行)
./deploy_opend.sh first-login
        ↓
输入短信验证码（或用 input_phone_verify_code 直接发送）
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
| `rebuild` | 重新构建镜像并启动（优先用本地包，否则下载 OpenD） |
| `logs` | 查看容器日志 |
| `status` / `ps` | 查看容器状态 |
| `exec` | 进入容器 Shell |

**OpenD 命令**

| 命令 | 说明 |
|------|------|
| `first-login` | 等待 OpenD 检测到需要短信验证后，交互式输入验证码 |
| `input_phone_verify_code -code=XXXXXX` | 直接发送短信验证码 |
| `opend-logs` | 查看 OpenD GTW 日志 |

**示例**

```bash
# 使用指定环境文件启动
./deploy_opend.sh -e .env.prod start

# 查看 OpenD 实时日志
./deploy_opend.sh opend-logs
```

## opend_ctl.sh 命令说明

容器内通过 `/app/opend_ctl.sh` 管理 opend：

```bash
/app/opend_ctl.sh <命令>
```

| 命令 | 说明 |
|------|------|
| `status` | 查看 FutuOpenD 进程状态 |
| `log` | 查看最近 GTW 日志 |
| `enable-rsa` | 启用 RSA 加密（需重启容器生效） |
| `disable-rsa` | 禁用 RSA 加密（需重启容器生效） |

## 端口说明

| 端口 | 用途 |
|------|------|
| 11111 | OpenD API 端口，供 SDK 连接 |
| 22222 | Telnet 管理端口，用于发送短信验证码 |

## 文件结构

```
.
├── docker-compose.yml      # Docker Compose 配置
├── Dockerfile              # 镜像构建文件（含 OpenD 下载）
├── deploy_opend.sh         # 部署管理脚本
├── generate_futu_pwd_md5.py # 密码 MD5 生成工具
├── .env                    # 环境变量配置（不提交到版本控制）
├── .futu_private_key.pem   # 富途私钥（可选，不提交到版本控制）
├── start.sh                # 容器启动脚本
├── opend_ctl.sh            # OpenD 控制脚本（容器内使用）
└── logs/                   # 日志目录
```

## 注意事项

1. 请妥善保管 `.env` 和私钥文件，不要提交到版本控制
2. 换版本时修改 `.env` 中的 `FUTU_OPEND_DOWNLOAD_URL` 和 `FUTU_OPEND_PKG_NAME`，然后执行 `rebuild`
3. OpenD 数据目录（`opend-data` volume）持久化了设备标识，重建容器后无需重新短信验证
4. 本地离线包（`Futu_OpenD_xxx.tar.gz`）无需提交到版本控制，已在 `.gitignore` 中忽略
