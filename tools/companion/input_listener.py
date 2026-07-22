#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
input_listener.py - 全局键鼠计数器（Raw Input / WM_INPUT 事件驱动版）

为什么用 Raw Input 而不是 GetAsyncKeyState 轮询：
  - 之前的轮询方案用 GetAsyncKeyState 的"低位锁存位"计数，那不是事件计数：
    两次采样之间同键按多次只计 1 次（漏计），按住/拖动时每次采样都 +1（虚高），
    结果随采样时机抖动、不稳定，远不如 Bongo Cat 准。
  - Raw Input 是事件驱动：每次真实按下 / 点击，系统投递一条 WM_INPUT，回调里
    精确 +1，与采样时机无关，逐次准确（Bongo Cat 级别的精度）。
  - 通过 RIDEV_INPUTSINK 注册，即使本进程不在前台也能收到，适合"后台统计"；
    不注入任何全局钩子（无 WH_KEYBOARD_LL），因此绝不会卡死鼠标键盘，也不受
    UIPI / 管理员权限影响。

实现要点（防坑）：
  - 所有 Windows API 显式声明 64 位 argtypes / restype（受管 Python 3.13 的
    ctypes.wintypes 缺 UINT_PTR / LRESULT，必须用 ctypes 基础类型替代，否则 import
    即崩）。
  - 早期把 stdout / stderr 重定向到 nul，避免继承父进程(Godot)管道写满导致启动阻塞。
  - 标准单线程消息泵 GetMessageW + SetTimer(WM_TIMER) 周期落盘；try/finally 清理
    窗口 / 类 / 设备注册，进程被杀(TerminateProcess)即停。
  - JSON 用 .tmp + os.replace 原子写，避免游戏侧读到写了一半的文件。

仅统计"发生了几次按下 / 点击"，绝不记录按键内容（隐私 / 杀软友好）。

用法：
  python input_listener.py [counts_path] [dump_ms]
  - counts_path: 统计结果写入的 JSON 路径（默认系统临时目录 fz_input_counts.json）
  - dump_ms:     JSON 落盘间隔毫秒（默认 250；与计数精度无关，只影响游戏读取频率，建议 >=50）

输出 JSON：
  {"running": true, "keys": 123, "mouse": 45, "error": ""}
"""

import ctypes
import json
import os
import sys
import tempfile

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
kernel32 = ctypes.windll.kernel32

# ── 显式 64 位类型（不依赖 wintypes 缺失成员） ──
HWND = ctypes.c_void_p
HINSTANCE = ctypes.c_void_p
LRESULT = ctypes.c_int64
WPARAM = ctypes.c_uint64
LPARAM = ctypes.c_int64
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, HWND, ctypes.c_uint, WPARAM, LPARAM)


# ── 常量 ──
RIM_TYPEMOUSE = 0
RIM_TYPEKEYBOARD = 1
RID_INPUT = 0x10000003
WM_INPUT = 0x00FF
WM_TIMER = 0x0113
WM_QUIT = 0x0012
RI_KEY_BREAK = 0x01
RIDEV_INPUTSINK = 0x00000100
RI_MOUSE_LEFT_BUTTON_DOWN = 0x0001
RI_MOUSE_RIGHT_BUTTON_DOWN = 0x0004
RI_MOUSE_MIDDLE_BUTTON_DOWN = 0x0010
RI_MOUSE_BUTTON_4_DOWN = 0x0040
RI_MOUSE_BUTTON_5_DOWN = 0x0100

# 这些"开关键"不算"打字输入"，统计键数时跳过（与之前一致）
_LOCK_KEYS = frozenset((0x14, 0x90, 0x91))  # CapsLock / NumLock / ScrollLock

state = {"running": True, "keys": 0, "mouse": 0, "error": ""}
_PATH = ""


# ── 结构体 ──
class RAWINPUTHEADER(ctypes.Structure):
    _fields_ = [
        ("dwType", ctypes.c_uint),
        ("dwSize", ctypes.c_uint),
        ("hDevice", HWND),
        ("wParam", WPARAM),
    ]


class RAWKEYBOARD(ctypes.Structure):
    _fields_ = [
        ("MakeCode", ctypes.c_ushort),
        ("Flags", ctypes.c_ushort),
        ("Reserved", ctypes.c_ushort),
        ("VKey", ctypes.c_ushort),
        ("Message", ctypes.c_uint),
        ("ExtraInformation", ctypes.c_ulong),
    ]


class RAWMOUSE(ctypes.Structure):
    _fields_ = [
        ("usFlags", ctypes.c_ushort),
        ("usButtonFlags", ctypes.c_ushort),
        ("usButtonData", ctypes.c_ushort),
        ("ulRawButtons", ctypes.c_ulong),
        ("lLastX", ctypes.c_long),
        ("lLastY", ctypes.c_long),
        ("ulExtraInformation", ctypes.c_ulong),
    ]


class _RAWUNION(ctypes.Union):
    _fields_ = [
        ("mouse", RAWMOUSE),
        ("keyboard", RAWKEYBOARD),
    ]


class RAWINPUT(ctypes.Structure):
    _fields_ = [
        ("header", RAWINPUTHEADER),
        ("u", _RAWUNION),
    ]


class RAWINPUTDEVICE(ctypes.Structure):
    _fields_ = [
        ("usUsagePage", ctypes.c_ushort),
        ("usUsage", ctypes.c_ushort),
        ("dwFlags", ctypes.c_uint),
        ("hwndTarget", HWND),
    ]


class WNDCLASSW(ctypes.Structure):
    _fields_ = [
        ("style", ctypes.c_uint),
        ("lpfnWndProc", WNDPROC),
        ("cbClsExtra", ctypes.c_int),
        ("cbWndExtra", ctypes.c_int),
        ("hInstance", HINSTANCE),
        ("hIcon", HWND),
        ("hCursor", HWND),
        ("hbrBackground", HWND),
        ("lpszMenuName", ctypes.c_wchar_p),
        ("lpszClassName", ctypes.c_wchar_p),
    ]


class MSG(ctypes.Structure):
    _fields_ = [
        ("hwnd", HWND),
        ("message", ctypes.c_uint),
        ("wParam", WPARAM),
        ("lParam", LPARAM),
        ("time", ctypes.c_uint),
        ("pt_x", ctypes.c_long),
        ("pt_y", ctypes.c_long),
    ]


# ── API 签名声明（64 位，避免截断） ──
user32.RegisterClassW.argtypes = (ctypes.POINTER(WNDCLASSW),)
user32.RegisterClassW.restype = ctypes.c_ushort  # ATOM；0 表示失败

user32.CreateWindowExW.argtypes = (
    ctypes.c_uint, ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint,
    ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    HWND, HWND, HINSTANCE, HWND,
)
user32.CreateWindowExW.restype = HWND

user32.DefWindowProcW.argtypes = (HWND, ctypes.c_uint, WPARAM, LPARAM)
user32.DefWindowProcW.restype = LRESULT

user32.GetMessageW.argtypes = (ctypes.POINTER(MSG), HWND, ctypes.c_uint, ctypes.c_uint)
user32.GetMessageW.restype = ctypes.c_int  # -1 错误，0 退出

user32.TranslateMessage.argtypes = (ctypes.POINTER(MSG),)
user32.TranslateMessage.restype = ctypes.c_int

user32.DispatchMessageW.argtypes = (ctypes.POINTER(MSG),)
user32.DispatchMessageW.restype = LRESULT

user32.SetTimer.argtypes = (HWND, WPARAM, ctypes.c_uint, ctypes.c_void_p)
user32.SetTimer.restype = WPARAM  # 0 表示失败

user32.KillTimer.argtypes = (HWND, WPARAM)
user32.KillTimer.restype = ctypes.c_int

user32.DestroyWindow.argtypes = (HWND,)
user32.DestroyWindow.restype = ctypes.c_int

user32.UnregisterClassW.argtypes = (ctypes.c_wchar_p, HINSTANCE)
user32.UnregisterClassW.restype = ctypes.c_int

user32.RegisterRawInputDevices.argtypes = (
    ctypes.POINTER(RAWINPUTDEVICE), ctypes.c_uint, ctypes.c_uint)
user32.RegisterRawInputDevices.restype = ctypes.c_int  # BOOL

user32.GetRawInputData.argtypes = (
    HWND, ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint), ctypes.c_uint)
user32.GetRawInputData.restype = ctypes.c_uint  # 字节数；0xFFFFFFFF 表示失败

kernel32.GetLastError.argtypes = ()
kernel32.GetLastError.restype = ctypes.c_uint

kernel32.GetModuleHandleW.argtypes = (ctypes.c_wchar_p,)
kernel32.GetModuleHandleW.restype = HINSTANCE

HWND_MESSAGE = HWND(-3)  # ((HWND)(LONG_PTR)-3)
_CLASS_NAME = "FzRawInputWnd"


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


def _on_wm_input(lparam):
    """解析一条 WM_INPUT，对每次按下 / 点击精确 +1。"""
    size = ctypes.c_uint(0)
    # 第一次调用拿所需缓冲区大小
    if user32.GetRawInputData(lparam, RID_INPUT, None, ctypes.byref(size),
                              ctypes.sizeof(RAWINPUTHEADER)) != 0:
        return
    if size.value == 0:
        return
    buf = ctypes.create_string_buffer(size.value)
    got = user32.GetRawInputData(lparam, RID_INPUT, buf, ctypes.byref(size),
                                 ctypes.sizeof(RAWINPUTHEADER))
    if got == 0xFFFFFFFF or got != size.value:
        return
    ri = ctypes.cast(buf, ctypes.POINTER(RAWINPUT)).contents
    if ri.header.dwType == RIM_TYPEKEYBOARD:
        kb = ri.u.keyboard
        # Flags 最低位 = RI_KEY_BREAK(1) 表示释放；否则为按下
        if (kb.Flags & RI_KEY_BREAK) == 0:
            vk = kb.VKey
            if vk not in _LOCK_KEYS:
                state["keys"] += 1
    elif ri.header.dwType == RIM_TYPEMOUSE:
        bf = ri.u.mouse.usButtonFlags
        if bf & RI_MOUSE_LEFT_BUTTON_DOWN:
            state["mouse"] += 1
        if bf & RI_MOUSE_RIGHT_BUTTON_DOWN:
            state["mouse"] += 1
        if bf & RI_MOUSE_MIDDLE_BUTTON_DOWN:
            state["mouse"] += 1
        if bf & RI_MOUSE_BUTTON_4_DOWN:
            state["mouse"] += 1
        if bf & RI_MOUSE_BUTTON_5_DOWN:
            state["mouse"] += 1


def _wndproc(hwnd, msg, wparam, lparam):
    try:
        if msg == WM_INPUT:
            _on_wm_input(lparam)
        elif msg == WM_TIMER:
            _dump(_PATH)
    except Exception:
        pass
    return user32.DefWindowProcW(hwnd, msg, wparam, lparam)


_WNDPROC_REF = WNDPROC(_wndproc)


def main():
    global _PATH
    _PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        tempfile.gettempdir(), "fz_input_counts.json")
    dump_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 250
    if dump_ms < 50:
        dump_ms = 50

    # 进程一起先写一次 running:true（若后续设备注册失败，再覆盖 error）
    _dump(_PATH)

    hinst = kernel32.GetModuleHandleW(None)

    wc = WNDCLASSW()
    wc.lpfnWndProc = _WNDPROC_REF
    wc.hInstance = hinst
    wc.lpszClassName = _CLASS_NAME
    atom = user32.RegisterClassW(ctypes.byref(wc))
    if atom == 0:
        state["error"] = "RegisterClassW failed, code=%d" % kernel32.GetLastError()
        _dump(_PATH)
        return

    # message-only 窗口：用于接收 WM_INPUT，不显示、不抢焦点
    hwnd = user32.CreateWindowExW(
        0, _CLASS_NAME, None, 0, 0, 0, 0, 0, HWND_MESSAGE, None, hinst, None)
    if not hwnd:
        state["error"] = "CreateWindowExW failed, code=%d" % kernel32.GetLastError()
        _dump(_PATH)
        user32.UnregisterClassW(_CLASS_NAME, hinst)
        return

    # 注册键盘 + 鼠标原始输入；INPUTSINK 让后台也能收
    devices = (RAWINPUTDEVICE * 2)()
    devices[0].usUsagePage = 0x01
    devices[0].usUsage = 0x06  # 键盘
    devices[0].dwFlags = RIDEV_INPUTSINK
    devices[0].hwndTarget = hwnd
    devices[1].usUsagePage = 0x01
    devices[1].usUsage = 0x02  # 鼠标
    devices[1].dwFlags = RIDEV_INPUTSINK
    devices[1].hwndTarget = hwnd
    if user32.RegisterRawInputDevices(devices, 2, ctypes.sizeof(RAWINPUTDEVICE)) == 0:
        state["error"] = "RegisterRawInputDevices failed, code=%d" % kernel32.GetLastError()
        _dump(_PATH)
        user32.DestroyWindow(hwnd)
        user32.UnregisterClassW(_CLASS_NAME, hinst)
        return

    # 周期落盘（与计数精度无关，只影响游戏读取频率）
    user32.SetTimer(hwnd, 1, dump_ms, None)
    _dump(_PATH)  # 就绪：running:true, error:""

    try:
        msg = MSG()
        # GetMessageW 阻塞泵消息；进程被 OS.kill 强杀即停（不依赖 WM_QUIT）
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
    finally:
        user32.KillTimer(hwnd, 1)
        user32.DestroyWindow(hwnd)
        user32.UnregisterClassW(_CLASS_NAME, hinst)
        state["running"] = False
        _dump(_PATH)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # 任何意外也要写出 stopped 状态，绝不留下误导
        state["error"] = "unexpected: %r" % exc
        state["running"] = False
        try:
            _dump(_PATH if _PATH else os.path.join(
                tempfile.gettempdir(), "fz_input_counts.json"))
        except Exception:
            pass
