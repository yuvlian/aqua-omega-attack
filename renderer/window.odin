package renderer

import "core:mem"
import "core:sys/windows"

foreign import user32 "system:User32.lib"

@(default_calling_convention = "stdcall")
foreign user32 {
	UpdateLayeredWindow :: proc (
		hWnd: windows.HWND,
		hdcDst: windows.HDC,
		pptDst: ^windows.POINT,
		psize: ^windows.SIZE,
		hdcSrc: windows.HDC,
		pptSrc: ^windows.POINT,
		crKey: windows.COLORREF,
		pblend: ^windows.BLENDFUNCTION,
		dwFlags: windows.DWORD,
	) -> windows.BOOL ---
}

ULW_ALPHA :: 0x00000002

overlay_hwnd: windows.HWND

mouse_x:      f32
mouse_y:      f32
left_pressed: bool
left_held:    bool

prev_left_down: bool

CHAR_BUFFER_SIZE :: 256
char_buffer: [CHAR_BUFFER_SIZE]rune
char_count:  int
char_head:   int

present_memdc:   windows.HDC
present_hbitmap: windows.HBITMAP
present_bits:    rawptr
present_w:       int
present_h:       int

window_proc :: proc "system" (
	hwnd: windows.HWND,
	msg: windows.UINT,
	wparam: windows.WPARAM,
	lparam: windows.LPARAM,
) -> windows.LRESULT {
	switch msg {
	case windows.WM_DESTROY:
		windows.PostQuitMessage(0)
		return 0
	case windows.WM_CLOSE:
		windows.DestroyWindow(hwnd)
		return 0
	case windows.WM_CHAR:
		if char_count < CHAR_BUFFER_SIZE {
			tail := (char_head + char_count) % CHAR_BUFFER_SIZE
			char_buffer[tail] = rune(wparam)
			char_count += 1
		}
		return 0
	case windows.WM_SETCURSOR:
		windows.SetCursor(windows.LoadCursorA(nil, windows.IDC_ARROW))
		return 1
	case:
		return windows.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
}

window_create :: proc (
	title, class: cstring16,
	width, height: int,
) -> (windows.HWND, bool) {
	hinstance := cast(windows.HINSTANCE) windows.GetModuleHandleA(nil)

	wc: windows.WNDCLASSEXW
	wc.cbSize = cast(windows.UINT) size_of(windows.WNDCLASSEXW)
	wc.style = windows.CS_HREDRAW | windows.CS_VREDRAW
	wc.lpfnWndProc = window_proc
	wc.hInstance = hinstance
	wc.hCursor = windows.LoadCursorA(nil, windows.IDC_ARROW)
	wc.hbrBackground = cast(windows.HBRUSH) windows.GetStockObject(windows.BLACK_BRUSH)
	wc.lpszClassName = class

	if windows.RegisterClassExW(&wc) == 0 {
		return nil, false
	}

	hwnd := windows.CreateWindowExW(
		windows.WS_EX_LAYERED | windows.WS_EX_TOPMOST | windows.WS_EX_TOOLWINDOW,
		class,
		title,
		windows.WS_POPUP,
		0, 0, cast(windows.INT) width, cast(windows.INT) height,
		nil, nil, hinstance, nil,
	)
	if hwnd == nil {
		return nil, false
	}

	windows.ShowWindow(hwnd, windows.SW_SHOW)
	overlay_hwnd = hwnd
	return hwnd, true
}

present_init :: proc (w, h: int) -> bool {
	bi := windows.BITMAPINFO {
		bmiHeader = windows.BITMAPINFOHEADER {
			biSize        = cast(windows.DWORD) size_of(windows.BITMAPINFOHEADER),
			biWidth       = cast(windows.LONG) w,
			biHeight      = -cast(windows.LONG) h,
			biPlanes      = 1,
			biBitCount    = 32,
			biCompression = windows.BI_RGB,
		},
	}
	present_hbitmap = windows.CreateDIBSection(
		nil, &bi, windows.DIB_RGB_COLORS, &present_bits, nil, 0)
	if present_hbitmap == nil {
		return false
	}
	present_memdc = windows.CreateCompatibleDC(nil)
	if present_memdc == nil {
		windows.DeleteObject(cast(windows.HGDIOBJ) present_hbitmap)
		present_hbitmap = nil
		present_bits = nil
		return false
	}
	windows.SelectObject(present_memdc, cast(windows.HGDIOBJ) present_hbitmap)
	present_w = w
	present_h = h
	return true
}

present_frame :: proc (hwnd: windows.HWND, pixels: rawptr) {
	if hwnd == nil || present_bits == nil || pixels == nil {
		return
	}
	mem.copy(present_bits, pixels, present_w*present_h*4)

	size := windows.SIZE {
		cx = cast(windows.LONG) present_w,
		cy = cast(windows.LONG) present_h,
	}
	pt_src := windows.POINT {x = 0, y = 0}
	blend := windows.BLENDFUNCTION {
		BlendOp             = windows.AC_SRC_OVER,
		BlendFlags          = 0,
		SourceConstantAlpha = 255,
		AlphaFormat         = windows.AC_SRC_ALPHA,
	}

	UpdateLayeredWindow(
		hwnd,
		nil,
		nil,
		&size,
		present_memdc,
		&pt_src,
		0,
		&blend,
		ULW_ALPHA,
	)
}

present_destroy :: proc () {
	if present_memdc != nil {
		windows.DeleteDC(present_memdc)
		present_memdc = nil
	}
	if present_hbitmap != nil {
		windows.DeleteObject(cast(windows.HGDIOBJ) present_hbitmap)
		present_hbitmap = nil
	}
	present_bits = nil
}

window_pump_messages :: proc () -> bool {
	msg: windows.MSG
	for windows.PeekMessageW(&msg, nil, 0, 0, windows.PM_REMOVE) {
		if msg.message == windows.WM_QUIT {
			return false
		}
		windows.TranslateMessage(&msg)
		windows.DispatchMessageW(&msg)
	}
	return true
}

window_set_clickthrough :: proc (enabled: bool) {
	if overlay_hwnd == nil {
		return
	}
	style := windows.GetWindowLongPtrW(overlay_hwnd, windows.GWL_EXSTYLE)
	transparent := windows.LONG_PTR(windows.WS_EX_TRANSPARENT)
	if enabled {
		style |= transparent
	} else {
		style &~= transparent
	}
	windows.SetWindowLongPtrW(overlay_hwnd, windows.GWL_EXSTYLE, style)
}

window_foreground_pid :: proc () -> u32 {
	hwnd := windows.GetForegroundWindow()
	pid: windows.DWORD
	windows.GetWindowThreadProcessId(hwnd, &pid)
	return u32(pid)
}

window_destroy :: proc (hwnd: windows.HWND, class: cstring16) {
	present_destroy()
	if hwnd != nil {
		windows.DestroyWindow(hwnd)
	}
	windows.UnregisterClassW(class,
		cast(windows.HINSTANCE) windows.GetModuleHandleA(nil))
}

input_poll :: proc (hwnd: windows.HWND) {
	pt: windows.POINT
	windows.GetCursorPos(&pt)
	windows.ScreenToClient(hwnd, &pt)
	mouse_x = f32(pt.x)
	mouse_y = f32(pt.y)

	down := windows.GetAsyncKeyState(windows.VK_LBUTTON) < 0
	left_pressed = down && !prev_left_down
	left_held = down
	prev_left_down = down
}

char_poll :: proc () -> (rune, bool) {
	if char_count == 0 {
		return 0, false
	}
	r := char_buffer[char_head]
	char_head = (char_head + 1) % CHAR_BUFFER_SIZE
	char_count -= 1
	return r, true
}
