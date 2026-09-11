#!/usr/bin/env python3
"""FutuOpenD 图形验证码自动识别 sidecar。

背景: 密码输错后, 富途服务端会要求图形验证码, 即使改对密码也必须先通过验证码。
原理:
  1. 监控 GTW 日志, 检测"需要图形验证码"标记
  2. OpenD 会自动下载 PicVerifyCode.png; 若迟迟未下载, 通过 telnet 发送 req_pic_verify_code
  3. ddddocr OCR 识别图片内容(富途验证码为 4 位大写字母+数字)
  4. telnet 发送 input_pic_verify_code -code=XXXX 自动提交
  5. 识别错误时 OpenD 会自动换一张新图, 继续重试, 直到 CAPTCHA_MAX_RETRIES 上限

限制: 手机短信验证码(首次登录/新设备)仍需人工输入:
  ./deploy_opend.sh first-login
"""

import glob
import os
import re
import socket
import time

import ddddocr

OPEND_HOST = os.environ.get("OPEND_HOST", "futu-opend")
TELNET_PORT = int(os.environ.get("TELNET_PORT", "22222"))
DATA_DIR = os.environ.get("DATA_DIR", "/data")
MAX_RETRIES = int(os.environ.get("CAPTCHA_MAX_RETRIES", "10"))

POLL_INTERVAL = 1.0
REQ_FALLBACK_AFTER = 6.0
REQ_THROTTLE = 8.0

MARK_NEED_PIC = "需要图形验证码"
MARK_PIC_WRONG = "图形验证码错误"
MARK_NEED_PHONE = "需要手机验证码"
MARK_PHONE_SENT = "请求手机验证码成功"
MARK_READY = "ProgramStatusType_Ready"
# 验证码已通过但密码被拒的特征(此时绝不能再消耗登录机会)
MARK_PWD_REJECTS = ("密码不匹配", "登录出错已达上限")
SUCCESS_MARKS = (MARK_NEED_PHONE, MARK_PHONE_SENT, MARK_READY)

MARKER_RE = re.compile(
    "(" + "|".join(re.escape(m) for m in [MARK_NEED_PIC, MARK_PIC_WRONG] + list(SUCCESS_MARKS)) + ")"
)


def log(msg):
    print(f"[captcha-solver] {msg}", flush=True)


_last_err = {"msg": None, "ts": 0.0}


def log_throttled(msg):
    """同类错误 30 秒内只打印一次, 避免 OpenD 重启期间刷屏。"""
    now = time.time()
    if msg == _last_err["msg"] and now - _last_err["ts"] < 30.0:
        return
    _last_err["msg"] = msg
    _last_err["ts"] = now
    log(msg)


_ocr = None


def get_ocr():
    global _ocr
    if _ocr is None:
        _ocr = ddddocr.DdddOcr(show_ad=False)
    return _ocr


def telnet_cmd(cmd):
    """向 OpenD telnet 控制台发送命令, 返回响应文本。"""
    with socket.create_connection((OPEND_HOST, TELNET_PORT), timeout=5) as s:
        s.settimeout(2.0)
        s.sendall((cmd + "\r\n").encode())
        chunks = []
        deadline = time.time() + 3.0
        while time.time() < deadline:
            try:
                data = s.recv(4096)
            except socket.timeout:
                break
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks).decode("utf-8", errors="ignore")


class LogWatcher:
    """增量读取最新 GTW 日志, 返回自上次调用以来的新增内容。"""

    def __init__(self, data_dir):
        self.data_dir = data_dir
        self.path = None
        self.offset = 0
        self.carry = b""

    def _latest(self):
        files = glob.glob(os.path.join(self.data_dir, "Log", "GTWLog_*.log"))
        return max(files, key=os.path.getmtime) if files else None

    def poll(self):
        path = self._latest()
        if path is None:
            return ""
        if path != self.path:
            self.path = path
            # 新日志文件只回放末尾 512KB, 用于恢复未完成的验证码会话
            self.offset = max(0, os.path.getsize(path) - 512 * 1024)
            self.carry = b""
        try:
            size = os.path.getsize(path)
        except OSError:
            return ""
        if size <= self.offset:
            return ""
        with open(path, "rb") as f:
            f.seek(self.offset)
            fresh = f.read()
        self.offset += len(fresh)
        blob = self.carry + fresh
        text = blob.decode("utf-8", errors="ignore")
        # 保留尾部字节, 避免中文标记被读取边界截断
        self.carry = blob[-64:]
        return text


def latest_png():
    files = glob.glob(os.path.join(DATA_DIR, "*", "PicVerifyCode.png"))
    return max(files, key=os.path.getmtime) if files else None


def read_png_stable(path):
    """等待图片写完(两次读取大小一致)并返回内容。"""
    for _ in range(10):
        try:
            size1 = os.path.getsize(path)
            time.sleep(0.15)
            size2 = os.path.getsize(path)
            if size1 == size2 and size1 > 0:
                with open(path, "rb") as f:
                    return f.read()
        except OSError:
            pass
        time.sleep(0.15)
    return None


def main():
    log(f"启动: opend={OPEND_HOST}:{TELNET_PORT} data={DATA_DIR} max_retries={MAX_RETRIES}")
    watcher = LogWatcher(DATA_DIR)

    state = {
        "episode_active": False,
        "attempts": 0,
        "gave_up": False,
        "last_activity": 0.0,
        "last_req_sent": 0.0,
        "last_png_mtime": 0.0,
        "phone_requested": False,
    }

    def request_phone_verify():
        """验证码通过后自动触发手机验证码短信, 用户只需查收短信并输入。"""
        if state["phone_requested"]:
            return
        state["phone_requested"] = True
        try:
            resp = telnet_cmd("req_phone_verify_code")
            if "成功" in resp or "已发送" in resp:
                log("已自动请求手机短信验证码, 请查收短信后输入: ./deploy_opend.sh input_phone_verify_code -code=XXXXXX")
            else:
                log(f"手机验证码请求响应: {resp.strip()[:120]!r}")
        except OSError as e:
            state["phone_requested"] = False
            log_throttled(f"telnet 请求手机验证码失败: {e}")

    def handle_text(text):
        if not text:
            return
        for m in MARKER_RE.finditer(text):
            tok = m.group(1)
            state["last_activity"] = time.time()
            if tok in SUCCESS_MARKS:
                if state["episode_active"] or state["gave_up"]:
                    log(f"检测到标记 [{tok}], 验证码会话结束")
                state["episode_active"] = False
                state["attempts"] = 0
                state["gave_up"] = False
                if tok == MARK_NEED_PHONE:
                    request_phone_verify()
                elif tok == MARK_PHONE_SENT:
                    state["phone_requested"] = True
            elif tok == MARK_NEED_PIC:
                if state["gave_up"]:
                    log("检测到新的图形验证码需求, 重新开始自动识别")
                    state["gave_up"] = False
                    state["attempts"] = 0
                if not state["episode_active"]:
                    log("检测到[需要图形验证码], 开始自动识别")
                state["episode_active"] = True
                state["phone_requested"] = False

    def solve(png_path):
        if state["attempts"] >= MAX_RETRIES:
            if not state["gave_up"]:
                state["gave_up"] = True
                log(f"已达最大重试次数({MAX_RETRIES}), 停止自动识别, 请手动处理:")
                log("  ./deploy_opend.sh exec 后执行: telnet 127.0.0.1 22222")
                log("  然后依次输入 req_pic_verify_code / input_pic_verify_code -code=XXXX")
            return
        state["attempts"] += 1
        log(f"自动识别第 {state['attempts']}/{MAX_RETRIES} 次: {png_path}")
        data = read_png_stable(png_path)
        try:
            state["last_png_mtime"] = os.path.getmtime(png_path)
        except OSError:
            pass
        if not data:
            log("读取验证码图片失败, 等待下次刷新")
            return
        try:
            code = get_ocr().classification(data)
        except Exception as e:
            log(f"OCR 失败: {e}")
            code = ""
        code = re.sub(r"[^0-9A-Za-z]", "", code or "").upper()
        if len(code) < 3:
            log(f"OCR 结果无效({code!r}), 请求换图重试")
            try:
                telnet_cmd("req_pic_verify_code")
                state["last_req_sent"] = time.time()
                state["last_activity"] = state["last_req_sent"]
            except OSError as e:
                log_throttled(f"telnet 请求失败: {e}")
            return
        log(f"识别结果: {code}, 自动提交...")
        try:
            resp = telnet_cmd(f"input_pic_verify_code -code={code}")
        except OSError as e:
            log_throttled(f"telnet 提交失败: {e}")
            return
        state["last_activity"] = time.time()
        if MARK_PIC_WRONG in resp:
            log("识别错误, OpenD 将自动换图, 继续重试")
        elif any(p in resp for p in MARK_PWD_REJECTS):
            log("图形验证码已通过, 但登录密码被服务端拒绝! 停止自动识别以避免消耗登录机会")
            log("请检查 .env 中的 FUTU_LOGIN_PWD 后重启; 若提示达上限需等待解锁")
            state["episode_active"] = False
            state["attempts"] = 0
            state["gave_up"] = True
        elif MARK_NEED_PHONE in resp:
            log("图形验证码通过! 自动请求手机短信验证码...")
            state["episode_active"] = False
            state["attempts"] = 0
            request_phone_verify()
        else:
            log(f"已提交, 等待日志确认结果 (响应: {resp.strip()[:120]!r})")

    # 启动时回放当前日志末尾, 恢复可能未完成的验证码会话
    handle_text(watcher.poll())
    png = latest_png()
    if state["episode_active"]:
        log("启动时检测到未完成的图形验证码会话, 将自动处理")
        state["last_png_mtime"] = 0.0
    elif png:
        state["last_png_mtime"] = os.path.getmtime(png)

    while True:
        handle_text(watcher.poll())

        png = latest_png()
        mtime = os.path.getmtime(png) if png else 0.0
        now = time.time()
        if (
            png
            and mtime > state["last_png_mtime"]
            and not state["gave_up"]
        ):
            # 验证码图片落盘/刷新本身即为独立触发源(不依赖日志标记格式)
            if not state["episode_active"]:
                log("检测到新的验证码图片, 开始自动识别")
                state["episode_active"] = True
            solve(png)
        elif state["episode_active"] and not state["gave_up"]:
            if now - state["last_activity"] > REQ_FALLBACK_AFTER and now - state["last_req_sent"] > REQ_THROTTLE:
                # 长时间没有新图片落盘, 主动请求一张验证码
                try:
                    telnet_cmd("req_pic_verify_code")
                    state["last_req_sent"] = now
                    state["last_activity"] = now
                    log("已发送 req_pic_verify_code 请求验证码图片")
                except OSError as e:
                    log_throttled(f"telnet 请求失败: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
