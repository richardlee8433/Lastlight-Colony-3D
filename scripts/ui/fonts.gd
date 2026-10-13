class_name Fonts
## UI font: Noto Sans TC cut down to the characters the game uses (fonts/NotoSansTC-UI.ttf,
## built by tools/subset_font.py), so English and Chinese render the same everywhere,
## including web builds where system fonts aren't available. System fonts are the fallback.

const UI_FONT := "res://fonts/NotoSansTC-UI.ttf"

static var _ui: Font

static func cjk() -> Font:
	if _ui == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["PingFang TC", "Heiti TC", "Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans TC", "sans-serif"])
		sys.font_weight = 500
		if ResourceLoader.exists(UI_FONT):
			var f: FontFile = load(UI_FONT)
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			f.fallbacks = [sys]
			_ui = f
		else:
			_ui = sys
	return _ui
