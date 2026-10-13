class_name Fonts
## System font with Traditional Chinese coverage (PingFang on macOS, JhengHei on Windows, Noto on Linux).

static var _cjk: SystemFont

static func cjk() -> SystemFont:
	if _cjk == null:
		_cjk = SystemFont.new()
		_cjk.font_names = PackedStringArray(["PingFang TC", "Heiti TC", "Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans TC", "Noto Sans CJK JP", "sans-serif"])
		_cjk.font_weight = 500
		_cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _cjk
