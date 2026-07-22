#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
input_listener.py - 全局键鼠计数器（Bongo Cat 同款，但用轮询而非全局钩子）

为什么用轮询而不是 SetWindowsHookExW（WH_KEYBOARD_LL / WH_MOUSE_LL）：
  - LL 全局钩子要求"装钩线程"持续泵消息循环，稍有差池（GIL 争用、循环缺陷、
    UIPI 跨权限注入失败）就会导致鼠标键盘全卡死，或钩子装上了回调却永不触发
    （计数始终为 0）。在受管 Python + 可能以管理员权限运行的父进程(Godot)下尤其
    不稳定。
  - 改用 GetAsyncKeyState 轮询：只"查询"全局异步输入状态，不注入任何钩子。
    * 不卡死（没有任何钩子要泵）；
    * 不受 UIPI / 管理员权限影响（查询不受完整性等级限制）；
    * 没有 64 位句柄 / GIL / 消息泵的坑；
    * 用返回值的"低位"锁存自上次查询以来的按下事件，连极快的点按也不会漏计。

用法：
  python input_listener.py [counts_path] [poll_ms]
  - counts_path: 统计结果写入的 JSON 路径（默认系统临时目录 fz_input_counts.json）
  - poll_ms:     轮询间隔（默认 50ms；建议 20~50ms，越小越不易漏掉极快点按）

输出 JSON：
  {"running": true, "keys": 123, "mouse": 45, "error": ""}

进程被杀（OS.kill / TerminateProcess）即停止；会话结束立刻退出（隐私/杀软友好）。
仅在活动会话期间运行，绝不记录按键内容，只累加"发生了几次按下/点击"。
"""
import ctypes
import ctypes.wintypes as wt
import json
import os
import sys
import tempfile
import time

# 早期重定向：避免继承自父进程(Godot)的管道写满导致启动阻塞
try:
    _devnull = open(os.devnull, "w")
    sys.stdout = _devnull
    sys.stderr = _devnull
except OSError:
    pass

# 非 Windows 直接报错退出（本游戏仅 Windows）
if not hasattr(ctypes, "windll"):
    try:
        with open(sys.argv[1] if len(sys.argv) > 1 else os.devnull, "w", encoding="utf-8") as f:
            json.dump({"running": False, "keys": 0, "mouse": 0, "error": "not Windows"}, f)
    except Exception:
        pass
    sys.exit(1)

user32 = ctypes.windll.user32
user32.GetAsyncKeyState.argtypes = (ctypes.c_int,)
user32.GetAsyncKeyState.restype = ctypes.c_short

# 鼠标按键虚拟键
VK_LBUTTON = 0x01
VK_RBUTTON = 0x02
VK_MBUTTON = 0x04

# 这些"开关键"不算"打字输入"，统计键数时跳过
_LOCK_KEYS = frozenset((0x14, 0x90, 0x91))  # CapsLock / NumLock / ScrollLock
# 鼠标按键的虚拟键（0x01~0x06）不计入"键盘"，改由下方鼠标段单独统计，避免重复
_MOUSE_VKS = frozenset((0x01, 0x02, 0x04, 0x05, 0x06))

state = {"running": True, "keys": 0, "mouse": 0, "error": ""}


def _dump(path):
    # 原子写：先写同目录 .tmp，再 os.replace，避免游戏侧读到写了一半的 JSON
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except OSError:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass


def _poll():
    # 键盘：GetAsyncKeyState 低位=自上次查询以来按过（锁存，连极快点按也不漏）
    for vk in range(256):
        if vk in _LOCK_KEYS or vk in _MOUSE_VKS:
            continue
        if user32.GetAsyncKeyState(vk) & 0x0001:
            state["keys"] += 1
    # 鼠标：左/右/中键的按下事件
    if user32.GetAsyncKeyState(VK_LBUTTON) & 0x0001:
        state["mouse"] += 1
    if user32.GetAsyncKeyState(VK_RBUTTON) & 0x0001:
        state["mouse"] += 1
    if user32.GetAsyncKeyState(VK_MBUTTON) & 0x0001:
        state["mouse"] += 1


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        tempfile.gettempdir(), "fz_input_counts.json")
    poll_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    if poll_ms < 10:
        poll_ms = 10

    # 进程一起就先写一次，便于游戏侧确认已启动、统计已就绪
    _dump(path)

    try:
        interval = poll_ms / 1000.0
        while True:
            _poll()
            _dump(path)
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally:
        state["running"] = False
        _dump(path)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # 任何意外也要写出 stopped 状态，绝不留下误导
        state["error"] = "unexpected: %r" % exc
        state["running"] = False
        try:
            _dump(sys.argv[1] if len(sys.argv) > 1 else os.path.join(
                tempfile.gettempdir(), "fz_input_counts.json"))
        except Exception:
            pass
