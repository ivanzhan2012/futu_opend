#!/usr/bin/env python3
"""
FutuOpenD 部署验证脚本
读取 .env 配置 → 检查 Docker 容器 → 检查 OpenD 进程 → 连接 API → 打印账户信息
"""

import os
import sys
import subprocess
from pathlib import Path

PASS = "[PASS]"
FAIL = "[FAIL]"
WARN = "[WARN]"
INFO = "[INFO]"

def separator(title=""):
    if title:
        print(f"\n── {title} {'─' * (50 - len(title))}")
    else:
        print("─" * 56)

# ── 1. 读取 .env ──────────────────────────────────────────────────────────────
env_file = Path(__file__).parent / ".env"
if not env_file.exists():
    print(f"{FAIL} 未找到 .env 文件: {env_file}")
    sys.exit(1)

config = {}
with open(env_file) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            config[k.strip()] = v.strip()

OPEND_HOST    = "127.0.0.1"
OPEND_PORT    = int(config.get("FUTU_OPEND_PORT", 11111))
RSA_ENABLE    = config.get("RSA_ENCRYPT_ENABLE", "false").lower() == "true"
PRIVATE_KEY   = config.get("FUTU_PRIVATE_KEY", "")
LOGIN_ACCOUNT = config.get("FUTU_LOGIN_ACCOUNT", "(未设置)")
CONTAINER     = config.get("CONTAINER_NAME", "futu-opend")

# ── 2. 打印配置摘要 ────────────────────────────────────────────────────────────
print("=" * 56)
print("  FutuOpenD 部署验证")
print("=" * 56)
print(f"  容器名称       : {CONTAINER}")
print(f"  OpenD 地址     : {OPEND_HOST}:{OPEND_PORT}")
print(f"  登录账号       : {LOGIN_ACCOUNT}")
rsa_status = f"已启用  (私钥: {PRIVATE_KEY})" if RSA_ENABLE else "未启用 (明文连接)"
print(f"  RSA 加密       : {rsa_status}")

# ── 3. 检查 Docker 容器状态 ───────────────────────────────────────────────────
separator("Docker 容器状态")

def run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return r.returncode, r.stdout.strip()
    except Exception as e:
        return -1, str(e)

ret, out = run(f"docker inspect --format='{{{{.State.Status}}}}' {CONTAINER} 2>/dev/null")
if ret != 0 or not out:
    print(f"{FAIL} 容器 {CONTAINER!r} 不存在或 docker 不可用")
    sys.exit(1)

container_status = out.strip("'")
health_ret, health_out = run(
    f"docker inspect --format='{{{{.State.Health.Status}}}}' {CONTAINER} 2>/dev/null"
)
health_status = health_out.strip("'") if health_ret == 0 else "unknown"

status_icon = PASS if container_status == "running" else FAIL
print(f"  {status_icon} 容器状态: {container_status}  健康检查: {health_status}")

if container_status != "running":
    print(f"\n  请先启动容器: docker-compose up -d")
    sys.exit(1)

# ── 4. 检查容器内 FutuOpenD 进程 ─────────────────────────────────────────────
separator("FutuOpenD 进程状态")

ret, pid_out = run(f"docker exec {CONTAINER} pgrep -x FutuOpenD")
opend_running = ret == 0 and pid_out.strip() != ""

if opend_running:
    pids = pid_out.strip().replace("\n", ", ")
    print(f"  {PASS} FutuOpenD 运行中  PID: {pids}")

    # 显示进程资源占用
    ret2, ps_out = run(
        f"docker exec {CONTAINER} ps -o pid,user,%cpu,%mem,etime --no-headers -p {pids.split(',')[0].strip()}"
    )
    if ret2 == 0 and ps_out:
        print(f"       {'PID':>6}  {'USER':<10} {'%CPU':>5} {'%MEM':>5}  {'ELAPSED':>10}")
        print(f"       {ps_out}")
else:
    print(f"  {FAIL} FutuOpenD 未在容器内运行")

    # 检查 supervisor autostart 配置
    ret3, sup_out = run(
        f"docker exec {CONTAINER} grep -m1 autostart /etc/supervisor/conf.d/supervisor_opend.conf"
    )
    if "autostart=false" in sup_out:
        print(f"\n  {WARN} Supervisor autostart=false，需要手动启动 OpenD：")
        print(f"       docker exec -it {CONTAINER} /app/opend_ctl.sh start")
        print(f"\n  若是首次部署，需先完成手机短信验证：")
        print(f"       docker exec -it {CONTAINER} /app/opend_ctl.sh first-login")
    sys.exit(1)

# ── 5. 检查登录状态（最近一次 GTW 日志） ─────────────────────────────────────
separator("登录状态")

LOG_DIR = "/home/ubuntu/.com.futunn.FutuOpenD/Log"

# 取最近一个 GTW 日志（按修改时间倒序）
ret_ls, latest_gtw = run(
    f"docker exec {CONTAINER} sh -c "
    f"\"ls -t {LOG_DIR}/GTWLog_*.log 2>/dev/null | head -1\""
)
if ret_ls != 0 or not latest_gtw:
    print(f"  {FAIL} 未找到 GTW 日志文件")
    print(f"\n  请执行首次登录: ./deploy_opend.sh first-login")
    sys.exit(1)

print(f"  {INFO} 最近日志: {latest_gtw.split('/')[-1]}")

# 检查最近日志中是否需要短信验证（首次登录未完成的标志）
ret_sms, _ = run(
    f"docker exec {CONTAINER} grep -q 'req_phone_verify_code' {latest_gtw}"
)
needs_sms = ret_sms == 0

# 检查最近日志是否达到 Ready 状态
ret_ready, _ = run(
    f"docker exec {CONTAINER} grep -q 'ProgramStatusType_Ready' {latest_gtw}"
)
is_ready = ret_ready == 0

if is_ready:
    print(f"  {PASS} 当前会话已成功登录 (ProgramStatusType_Ready)")
elif needs_sms:
    print(f"  {FAIL} 当前会话需要短信验证码，首次登录未完成")
    print(f"\n  请执行首次登录: ./deploy_opend.sh first-login")
    sys.exit(1)
else:
    print(f"  {WARN} 当前会话未达到 Ready 状态（可能正在登录中）")

# ── 6. 连接 OpenD API ─────────────────────────────────────────────────────────
separator("API 连接测试")

import futu
import logging
import signal

logging.getLogger("FTConsoleLog").setLevel(logging.CRITICAL)

if RSA_ENABLE:
    if not PRIVATE_KEY:
        print(f"  {WARN} RSA_ENCRYPT_ENABLE=true 但 FUTU_PRIVATE_KEY 未配置")
        sys.exit(1)
    key_path = Path(PRIVATE_KEY)
    if not key_path.exists():
        print(f"  {FAIL} 私钥文件不存在: {PRIVATE_KEY}")
        sys.exit(1)
    futu.SysConfig.set_init_rsa_file(str(key_path))
    futu.SysConfig.enable_proto_encrypt(str(key_path))
    print(f"  {INFO} 已启用 RSA 加密 (私钥: {PRIVATE_KEY})")
else:
    print(f"  {INFO} 未启用 RSA 加密（明文连接）")

API_TIMEOUT = 15

def _timeout_handler(signum, frame):
    raise TimeoutError("API 连接超时")

old_handler = signal.signal(signal.SIGALRM, _timeout_handler)
try:
    signal.alarm(API_TIMEOUT)
    quote_ctx = futu.OpenQuoteContext(host=OPEND_HOST, port=OPEND_PORT)
    signal.alarm(0)
except TimeoutError:
    print(f"  {FAIL} 连接 OpenD 超时 ({API_TIMEOUT}s)，OpenD 可能未完成登录或正在等待验证码")
    sys.exit(1)
except Exception as e:
    signal.alarm(0)
    print(f"  {FAIL} 连接 OpenD 失败: {e}")
    sys.exit(1)
finally:
    signal.signal(signal.SIGALRM, old_handler)

print(f"  {PASS} 成功连接 OpenD  {OPEND_HOST}:{OPEND_PORT}")

# ── 7. 全局状态 ───────────────────────────────────────────────────────────────
separator("全局状态")

old_handler = signal.signal(signal.SIGALRM, _timeout_handler)
try:
    signal.alarm(API_TIMEOUT)
    ret, state = quote_ctx.get_global_state()
    signal.alarm(0)
except TimeoutError:
    print(f"  {FAIL} 获取全局状态超时 ({API_TIMEOUT}s)，OpenD 可能处于登录中状态")
    quote_ctx.close()
    sys.exit(1)
finally:
    signal.signal(signal.SIGALRM, old_handler)

if ret == futu.RET_OK:
    KEY_MAP = {
        "market_sh":       "沪市状态",
        "market_sz":       "深市状态",
        "market_hk":       "港市状态",
        "market_us":       "美市状态",
        "server_ver":      "OpenD 版本",
        "sdk_ver":         "SDK 版本",
        "login_status":    "登录状态",
        "conn_id":         "连接 ID",
        "conn_key":        "连接密钥",
    }
    for key, label in KEY_MAP.items():
        if key in state:
            print(f"  {label:<12}: {state[key]}")

    program_status = state.get("program_status")
    if program_status and "Ready" not in str(program_status):
        print(f"\n  {WARN} 程序状态: {program_status} (非 Ready，登录可能未完成)")
else:
    print(f"  {WARN} 获取全局状态失败: {state}")

# ── 8. 账户信息 ───────────────────────────────────────────────────────────────
separator("交易账户")

# OpenD 监听 0.0.0.0 时，从宿主机经 Docker NAT 连入的交易连接会被视为跨网请求，
# 强制要求 RSA 加密。行情连接无此限制，因此 quote_ctx 可正常使用。
CROSS_NET_MSG = "跨网通信"

def _query_accounts(host, port):
    """返回 (total, error_msg)，error_msg 为 None 表示成功。"""
    trade_ctx = None
    total = 0
    try:
        trade_ctx = futu.OpenSecTradeContext(
            filter_trdmarket=futu.TrdMarket.HK,
            host=host,
            port=port,
        )
        ret, accs = trade_ctx.get_acc_list()
        if ret != futu.RET_OK:
            err = str(accs)
            if CROSS_NET_MSG in err:
                return 0, err
            return 0, f"查询账户失败: {accs}"
        try:
            rows = accs if isinstance(accs, list) else accs.to_dict("records")
        except Exception:
            rows = []
        if not rows:
            return 0, None
        total = len(rows)
        # 按环境分组展示
        env_groups: dict = {}
        for row in rows:
            if isinstance(row, dict):
                env_key = str(row.get("trd_env", "未知"))
                env_groups.setdefault(env_key, []).append(row)
        for env_key, group in env_groups.items():
            print(f"\n  {env_key} ({len(group)} 个账户):")
            for row in group:
                cols = ["acc_id", "trd_env", "acc_type", "card_num"]
                info = "  ".join(f"{c}={row[c]}" for c in cols if c in row)
                print(f"    · {info}")
        return total, None
    except Exception as e:
        err = str(e)
        if CROSS_NET_MSG in err:
            return 0, err
        return 0, f"未知异常: {err}"
    finally:
        if trade_ctx:
            trade_ctx.close()

total_accounts, acc_error = _query_accounts(OPEND_HOST, OPEND_PORT)

if acc_error and CROSS_NET_MSG in acc_error:
    print(f"  {WARN} 交易接口需要 RSA 加密（OpenD 监听 0.0.0.0，宿主机连接被视为跨网请求）")
    print(f"       解决方法：在 .env 中设置 RSA_ENCRYPT_ENABLE=true 并配置私钥路径")
elif acc_error:
    print(f"  {WARN} 查询账户时发生异常: {acc_error}")
elif total_accounts == 0:
    print(f"  {WARN} 未查询到任何账户（请确认账号已在 OpenD 完成登录）")
else:
    print(f"\n  {PASS} 共查询到 {total_accounts} 个交易账户")

# ── 9. 关闭连接 ───────────────────────────────────────────────────────────────
quote_ctx.close()

print()
print("=" * 56)
print(f"  {PASS} FutuOpenD 部署验证通过！")
print("=" * 56)
