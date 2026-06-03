# FutuOpenD Docker

富途 OpenD 服务的 Docker 容器化部署方案。

## 快速开始

按以下步骤顺序执行，即可完成首次部署。

### 步骤 1：复制配置文件

```bash
cp .env.example .env
```

### 步骤 2：生成密码 MD5

```bash
# 交互式（不回显明文）
python3 generate_futu_pwd_md5.py

# 或直接传参
python3 generate_futu_pwd_md5.py 你的密码
```

将输出的 32 位 MD5 填入 `.env` 的 `FUTU_LOGIN_PWD`。

### 步骤 3：填写账号

编辑 `.env`，填入以下必填项：

```ini
FUTU_LOGIN_ACCOUNT=你的富途账号
FUTU_LOGIN_PWD=上一步生成的MD5
```

### 步骤 4：生成 RSA 私钥

> 如需账户/交易功能，**必须启用 RSA 加密**（`.env.example` 默认已开启）。
> 仅看行情可跳过此步，并将 `RSA_ENCRYPT_ENABLE` 改为 `false`。

```bash
openssl genrsa 1024 | openssl pkcs8 -topk8 -nocrypt -out .futu_private_key.pem
```

生成后无需修改 `.env`——默认 `RSA_ENCRYPT_ENABLE=true` 且 `FUTU_PRIVATE_KEY` 已指向此文件。

API 客户端侧也需使用同一份私钥：

```python
# Python SDK 示例
futu.SysConfig.enable_proto_encrypt(".futu_private_key.pem")
```

### 步骤 5：构建镜像并启动容器

```bash
chmod +x deploy_opend.sh
./deploy_opend.sh rebuild
```

首次构建会自动下载 OpenD（约几分钟）。网络不稳定时可提前将 `.tar.gz` 包放到项目根目录，构建时自动使用本地文件。

### 步骤 6：首次短信验证

OpenD 首次在新设备启动需要短信验证码：

```bash
# 交互式（等待验证码提示后输入）
./deploy_opend.sh first-login

# 或直接发送验证码
./deploy_opend.sh input_phone_verify_code -code=123456
```

验证通过后，设备标识会持久化到 Docker volume，后续重建容器无需再次验证。

### 步骤 7：验证部署（可选）

```bash
python3 verify_opend.py
```

### 完成

服务已运行。之后只需：

```bash
./deploy_opend.sh start   # 启动
./deploy_opend.sh stop    # 停止
```

---

## 配置说明

`.env` 完整配置项：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `FUTU_LOGIN_ACCOUNT` | 富途登录账号 | （必填） |
| `FUTU_LOGIN_PWD` | 登录密码 MD5（通过 `generate_futu_pwd_md5.py` 生成） | （必填） |
| `RSA_ENCRYPT_ENABLE` | 启用 RSA 加密通信 | `true` |
| `FUTU_PRIVATE_KEY` | 私钥文件路径 | `./.futu_private_key.pem` |
| `FUTU_OPEND_PORT` | OpenD API 端口 | `11111` |
| `FUTU_TELNET_PORT` | Telnet 端口（短信验证用） | `22222` |
| `FUTU_OPEND_IP` | OpenD 监听 IP | `0.0.0.0` |
| `FUTU_TELNET_IP` | Telnet 监听 IP | `0.0.0.0` |
| `AUTO_HOLD_QUOTE_RIGHT` | 自动抢回高级行情权限（0/1） | `1` |
| `IMAGE_NAME` | 镜像名称 | `futu-opend` |
| `IMAGE_TAG` | 镜像标签 | `latest` |
| `RESTART_POLICY` | Docker 重启策略 | `unless-stopped` |
| `NETWORK_NAME` | Docker 网络名称 | `futu-network` |

---

## 命令参考

### deploy_opend.sh

```bash
./deploy_opend.sh [选项] <命令>

# 选项
-e, --env <file>    指定 .env 文件（默认: .env）
```

| 命令 | 说明 |
|------|------|
| `rebuild` | 构建镜像并启动（优先用本地包，否则下载） |
| `start` | 启动容器 |
| `stop` | 停止容器 |
| `restart` | 重启容器 |
| `logs` | 查看容器日志 |
| `status` / `ps` | 查看容器状态 |
| `exec` | 进入容器 Shell |
| `first-login` | 交互式短信验证 |
| `input_phone_verify_code -code=XXXXXX` | 直接发送验证码 |
| `opend-logs` | 查看 OpenD GTW 日志 |

### opend_ctl.sh（容器内）

```bash
/app/opend_ctl.sh <命令>
```

| 命令 | 说明 |
|------|------|
| `status` | 查看 OpenD 进程状态 |
| `log` | 查看最近 GTW 日志 |
| `enable-rsa` | 启用 RSA 加密（需重启容器） |
| `disable-rsa` | 禁用 RSA 加密（需重启容器） |

---

## 文件结构

```
.
├── deploy_opend.sh          # 部署管理脚本（宿主机使用）
├── docker-compose.yml       # Docker Compose 配置
├── Dockerfile               # 镜像构建文件
├── start.sh                 # 容器启动入口
├── opend_ctl.sh             # OpenD 控制脚本（容器内使用）
├── generate_futu_pwd_md5.py # 密码 MD5 生成工具
├── verify_opend.py          # 部署验证（容器进程 + API 连接）
├── .env.example             # 环境变量模板
├── .env                     # 实际配置（不提交 git）
├── .futu_private_key.pem    # RSA 私钥（不提交 git）
└── logs/                    # 日志目录
```

---

## 注意事项

1. `.env` 和 `.futu_private_key.pem` 不要提交到版本控制（已在 `.gitignore` 中排除）
2. 升级 OpenD 版本：修改 `.env` 中的 `FUTU_OPEND_DOWNLOAD_URL` 和 `FUTU_OPEND_PKG_NAME`，然后 `./deploy_opend.sh rebuild`
3. `opend-data` Docker volume 持久化了设备标识，重建容器无需重新短信验证
4. 同一台机器跑多个 OpenD 实例时，须使用不同项目目录或 `COMPOSE_PROJECT_NAME`，并错开 `FUTU_OPEND_PORT` / `FUTU_TELNET_PORT`，避免宿主机端口冲突
5. 本地离线包（`Futu_OpenD_xxx.tar.gz`）放项目根目录即可被构建自动识别，无需提交 git
