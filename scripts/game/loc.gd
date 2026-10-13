class_name Loc
## Localisation: the game is written in English; Loc.t() returns the Traditional Chinese
## text when that language is selected. Missing entries fall back to English.
## After adding Chinese text, re-run tools/subset_font.py so the bundled font has the glyphs.

const LANGS := {"en": "English", "zh": "中文"}
const SETTINGS_PATH := "user://settings.cfg"

static var lang := "en"

static func t(s: String) -> String:
	if lang == "zh":
		return ZH.get(s, s)
	return s

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var l: String = cfg.get_value("ui", "lang", "en")
		if LANGS.has(l): lang = l

static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "lang", lang)
	cfg.save(SETTINGS_PATH)

## Zh-TW text keyed by the English text used in the code (and in Defs).
const ZH := {
	"Edit forest area": "編輯林區",
	"Forest area %.0f m²  %d trees": "林區 %.0f m²  %d 棵樹",
	"Clear area": "清空林區",
	"Left-drag to paint the forest area (within %d m of the lodge) · X toggles erase (or hold Shift) · right-click / Esc to finish": "左鍵拖曳 畫林區（離伐木場 %d 公尺內）· X 切換擦除（或按住 Shift 拖曳）· 右鍵 / Esc 完成",
	"Forest area: %.0f m² (max %.0f m²)": "林區：%.0f m²（上限 %.0f m²）",
	"Trees: %d ready to fell, %d growing, %d stumps": "樹：%d 棵可砍、%d 棵生長中、%d 個樹樁",
	"Area too small: needs at least %.0f m²": "林區太小，至少要 %.0f m²",
	"Waiting for trees to grow": "等樹長大",
	"A forest area is ready. Drag to grow it; X or Shift to erase": "已畫好一塊林區，拖曳擴大，按 X 或 Shift 擦除",
	"No trees here yet. Saplings will sprout in the area, or paint it over a forest": "這裡還沒有樹。林區裡會慢慢冒出樹苗，也可以把林區畫到樹林上",
	"Area cleared": "已清空林區",
	"that's a forest area": "這裡是林區",
	"too far from the lodge": "離伐木場太遠",
	"another woodcutter's area": "別的林區",
	"farm field": "農田",
	"forest area": "林區",
	"%s (%s)": "%s（%s）",
	"Left-drag to paint the field (within %d m of the farmhouse) · X toggles erase (or hold Shift) · right-click / Esc to finish": "左鍵拖曳 畫田地（離農舍 %d 公尺內）· X 切換擦除（或按住 Shift 拖曳）· 右鍵 / Esc 完成",
	"Left-click select · 1-5 build · right-drag rotate camera · WASD / middle-drag pan · wheel zoom": "左鍵 選取建築 · 1-5 建造 · 右鍵拖曳 旋轉鏡頭 · WASD / 中鍵 平移 · 滾輪 縮放",
	"Left-click to place %s · R / Shift+R or Shift+wheel to rotate · right-click / Esc to cancel": "左鍵 放置%s · R / Shift+R 或 Shift+滾輪 旋轉 · 右鍵 / Esc 取消",
	"Left-drag to paint a housing zone · X toggles erase (or hold Shift) · right-click / Esc to finish": "左鍵拖曳 畫住宅區 · X 切換擦除（或按住 Shift 拖曳）· 右鍵 / Esc 完成",
	"Per trip: %d food (bigger field = more; closer storage = more trips)": "每趟搬回：%d 食物（田越大越多，倉庫越近趟數越多）",
	"Field: %.0f m² (max %.0f m²)": "田地：%.0f m²（上限 %.0f m²）",
	"%d bedrolls by the campfire. Paint a housing zone so villagers build homes": "營火旁有 %d 個睡鋪，畫住宅區讓村民蓋房子",
	"Field too small: needs at least %.0f m² to produce": "田地太小，至少要 %.0f m² 才有收成",
	"Per trip: %d %s (closer storage = more trips)": "每趟搬回：%d %s（倉庫越近，趟數越多）",
	"Field %.0f m²  %d food/trip": "田地 %.0f m²  每趟 %d 食物",
	"Pop  %d/%d   Jobs %d/%d": "人口  %d/%d   工作 %d/%d",
	"Delivered to storage yesterday (minus food eaten)": "昨天搬進倉庫的量（扣掉食物消耗）",
	"Delete the save and start over?": "確定要清除存檔、重新開始嗎？",
	"Nearby workers bring their goods here": "附近的工人會把資源搬來這裡",
	"  (%s%.0f/day)": "  (%s%.0f/天)",
	"Housing zone %.0f m²": "住宅區 %.0f m²",
	"No worker (needs more villagers)": "缺工人（需要更多人口）",
	"Demolish (refund half)": "拆除（退回一半資源）",
	"  (+%d/day)": "  (+%d/天)",
	"Houses %d people": "提供 %d 人居住",
	"Delivered to storage yesterday": "昨天搬進倉庫的量",
	"Keep building your village": "自由建造你的村莊",
	"Hungry, stopped": "餓肚子，停工中",
	"A new village begins": "新的村莊開始了",
	"Erase (X)": "擦除 (X)",
	"Day %d": "第 %d 天",
	"All quests done": "所有任務完成",
	"Restart": "重新開始",
	"Edit field": "編輯田地",
	"Clear field": "清空田地",
	"Clear all": "全部清除",
	"Reward: ": "獎勵：",
	"Working": "工作中",
	"Status: ": "狀態：",
	"Worker: ": "工人：",
	"Pause": "暫停",
	"Quest": "任務",
	"Done": "完成",
	"Cancel": "取消",
	"Paint": "畫",
	"none": "無",
	"A starter field is ready. Drag to grow it; X or Shift to erase": "已畫好一塊起始田地，拖曳擴大，按 X 或 Shift 擦除",
	"All housing zones cleared (built houses stay)": "已清除所有住宅區（已蓋好的房子會保留）",
	"too close to the village centre": "太靠近村莊中心",
	"overlaps another building": "和其他建築重疊",
	"trees or obstacles in the way": "有樹木或障礙物",
	"Field cleared": "已清空這塊田地",
	"out of bounds": "超出建造範圍",
	"Can't build here: ": "這裡不能蓋：",
	"that's a farm field": "這裡是農田",
	"No worker": "缺工人",
	"Hungry": "餓肚子",
	"All quests complete! Keep building freely": "所有任務完成！繼續自由建造吧",
	"Out of food! Only farmers keep working": "食物不足！只剩農夫還在工作",
	"%s demolished, half the cost refunded": "已拆除%s，退回一半資源",
	"Everyone has eaten. Back to work": "村民吃飽了，恢復工作",
	"A new villager moved in!": "一位新村民搬進村子！",
	"Quest complete: %s%s": "任務完成：%s%s",
	"Not enough resources: need ": "資源不足：需要 ",
	"%s can't be demolished": "%s不能拆除",
	"  Reward: ": "  獎勵 ",
	"too far from the farmhouse": "離農舍太遠",
	"out of range": "超出範圍",
	"another farm's field": "別的農田",
	"housing zone": "住宅區",
	"obstacle": "障礙物",
	"building": "建築",
	"Going to work": "前往工作",
	"Resting at home": "回家休息",
	"Leaving": "離開村子",
	"Chopping": "砍樹中",
	"Quarrying": "採石中",
	"Tending the field": "耕田中",
	"Hauling": "搬運中",
	"Just arrived": "剛搬來",
	"Strolling": "閒逛中",
	"Villagers built a new house": "村民在住宅區蓋了一間新房子",
	"Paint where people may live. When the village needs beds and can pay, villagers build houses there themselves (each: Wood 20, Stone 15)": "畫出住宅區。村子需要更多住處、資源也夠時，村民會自己在區域裡蓋房子（每間 木材 20 石材 15）",
	"After building it, paint its field. The farmer tends the wheat and carries the harvest to storage; bigger fields give more per trip": "蓋好後畫出田地。農夫照顧麥田，把收成背回倉庫；田越大每趟收成越多",
	"The settlers' supply cart: temporary storage, with 4 bedrolls by the campfire": "移民帶來的補給車：臨時倉庫，旁邊的營火有 4 個睡鋪",
	"Villagers haul goods to the nearest storage. Build one near production to shorten trips": "村民把資源搬到最近的倉庫，蓋在生產區旁邊可以縮短搬運",
	"Paint a forest area after building it. The woodcutter fells the grown trees inside and carries the logs to storage; stumps regrow and saplings sprout": "蓋好後畫出林區。伐木工砍林區裡長大的樹，扛回倉庫；樹樁會再長，空地會冒出樹苗",
	"Paint a housing zone and wait for a house": "畫一塊住宅區，等村民蓋房子",
	"The mason breaks off stone and hauls it to storage": "石匠敲下石塊，搬回倉庫",
	"Room for 4 villagers": "增加 4 人居住空間",
	"Build a farmhouse and paint its field": "蓋一座農舍並畫出田地",
	"Build a storehouse near production": "在生產區旁蓋一座倉庫",
	"Reach 10 villagers": "人口達到 10 人",
	"Stockpile 100 wood": "存到 100 木材",
	"Reach 20 villagers": "人口達到 20 人",
	"Have 3 farmhouses": "擁有 3 座農舍",
	"Build a woodcutter": "蓋一座伐木場",
	"Build a quarry": "蓋一座採石場",
	"Paint area": "畫出範圍",
	"Woodcutter": "伐木場",
	"Quarry": "採石場",
	"Supply cart": "補給車",
	"Housing zone": "住宅區",
	"Wood": "木材",
	"Stone": "石材",
	"Food": "食物",
	"Farmhouse": "農舍",
	"House": "民房",
	"Storehouse": "倉庫",
}
