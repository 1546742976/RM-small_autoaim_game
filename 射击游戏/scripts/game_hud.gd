extends CanvasLayer

signal start_requested
signal purchase_requested(weapon_id: String, armor: bool)
signal shop_closed
signal resume_requested
signal menu_requested
signal quit_requested

const Rules = preload("res://scripts/game_rules.gd")
const UI_FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const INK = Color("101b25")
const PANEL = Color("172733")
const LINE = Color("38505c")
const TEXT = Color("eef4f4")
const MUTED = Color("b3c6cc")
const ACCENT = Color("73e3ce")
const AMBER = Color("ffc577")

var root: Control
var overlay: Control
var hud: Control
var heading: Label
var clock_label: Label
var scores: Label
var ammo: Label
var vitals: Label
var velocity_label: Label
var permit_label: Label
var instructions: Label
var toast: Label
var crosshair: Label
var hit_marker: Label
var speed_bar: ProgressBar
var shop_money: Label
var shop_countdown: Label
var shop_confirm: Button
var shop_armor: CheckBox
var weapon_buttons: Dictionary = {}
var selected_weapon := "deagle"
var shop_locked := false
var toast_left := 0.0
var marker_left := 0.0
var overlay_kind := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", _box(PANEL, LINE))
	theme.set_stylebox("hover", "Button", _box(Color("263e48"), ACCENT))
	theme.set_stylebox("pressed", "Button", _box(Color("31544f"), ACCENT))
	theme.set_stylebox("disabled", "Button", _box(INK, LINE))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2))
	root.theme = theme
	_build_hud()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

func _box(color: Color, border: Color = LINE, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 48
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	return node

func _panel_at(parent: Control, preset: int, offsets: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = offsets.position.x
	panel.offset_top = offsets.position.y
	panel.offset_right = offsets.end.x
	panel.offset_bottom = offsets.end.y
	panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.08, 0.11, 0.92)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var top := _panel_at(hud, Control.PRESET_TOP_WIDE, Rect2(24, 20, -48, 80))
	var row := HBoxContainer.new()
	top.add_child(row)
	heading = _label("RM / PRECISION LAB", 20, ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	scores = _label("击杀  0     命中率  0%", 18)
	row.add_child(scores)
	clock_label = _label("   60.0", 28, AMBER)
	clock_label.custom_minimum_size.x = 140
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(clock_label)
	var left := _panel_at(hud, Control.PRESET_BOTTOM_LEFT, Rect2(24, -150, 310, 126))
	var left_column := VBoxContainer.new()
	left.add_child(left_column)
	velocity_label = _label("速度比  0.000 / 0.340", 19)
	left_column.add_child(velocity_label)
	speed_bar = ProgressBar.new()
	speed_bar.custom_minimum_size.y = 8
	speed_bar.max_value = 1.0
	speed_bar.show_percentage = false
	var track := _box(LINE, LINE, 0)
	var fill := _box(ACCENT, ACCENT, 0)
	for style in [track, fill]:
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		style.content_margin_left = 0
		style.content_margin_right = 0
	speed_bar.add_theme_stylebox_override("background", track)
	speed_bar.add_theme_stylebox_override("fill", fill)
	left_column.add_child(speed_bar)
	permit_label = _label("可以精准开火", 19, ACCENT)
	left_column.add_child(permit_label)
	var right := _panel_at(hud, Control.PRESET_BOTTOM_RIGHT, Rect2(-324, -150, 300, 126))
	var right_column := VBoxContainer.new()
	right.add_child(right_column)
	ammo = _label("沙鹰   07 / 14", 24)
	right_column.add_child(ammo)
	vitals = _label("生命 100     护甲 0", 18, MUTED)
	right_column.add_child(vitals)
	instructions = _label("WASD 移动 · 左键单发 · R 换弹 · Esc 暂停", 16, MUTED)
	hud.add_child(instructions)
	instructions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	instructions.offset_left = -310
	instructions.offset_right = 310
	instructions.offset_top = -45
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair = _label("＋", 24, ACCENT)
	hud.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -20
	crosshair.offset_right = 20
	crosshair.offset_top = -20
	crosshair.offset_bottom = 20
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hit_marker = _label("×", 40, AMBER)
	hud.add_child(hit_marker)
	hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_marker.offset_left = -30
	hit_marker.offset_right = 30
	hit_marker.offset_top = -30
	hit_marker.offset_bottom = 30
	hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hit_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hit_marker.hide()
	toast = _label("", 20, AMBER)
	hud.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast.offset_left = -490
	toast.offset_right = 490
	toast.offset_top = 60
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _clear_overlay(kind: String) -> VBoxContainer:
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay_kind = kind
	overlay.show()
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.035, 0.05, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 880
	panel.add_theme_stylebox_override("panel", _box(INK, LINE))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	return column

func show_menu() -> void:
	hud.hide()
	var column := _clear_overlay("menu")
	column.add_child(_label("RM  /  PRECISION LAB                                     TRAINING 01", 17, ACCENT))
	column.add_child(_label("先停稳，再命中。", 48))
	column.add_child(_label("急停射击训练场", 25, MUTED))
	column.add_child(HSeparator.new())
	column.add_child(_label("01  控制移动        02  速度比 < 0.34        03  单发命中", 22, AMBER))
	column.add_child(_label("三把武器 · 六个训练靶 · 六十秒挑战\n无随机散布，让每一次命中都来自你的判断。", 20, MUTED))
	column.add_child(_button("开始训练  →", func(): start_requested.emit()))
	column.add_child(_button("退出游戏", func(): quit_requested.emit()))
	column.add_child(_label("WASD 移动   /   鼠标瞄准   /   左键单发   /   R 换弹   /   Esc 暂停", 16, MUTED))

func show_buy(locked: bool, weapon_id: String, armor_value: int, money: int) -> void:
	hud.show()
	shop_locked = locked
	selected_weapon = weapon_id
	weapon_buttons.clear()
	var column := _clear_overlay("buy")
	shop_countdown = _label("01 / 装备准备     ·     倒计时结束后自动开始", 17, ACCENT)
	column.add_child(shop_countdown)
	column.add_child(_label("选择这回合的节奏", 32))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for id in ["deagle", "ak47", "m4a1"]:
		var data: Dictionary = Rules.WEAPONS[id]
		var cost: String = "默认免费" if id == "deagle" else "$%d" % data.price
		var button := _button("%s\n%s\n%d 发 / %d ms\n躯干伤害 %d" % [data.name, cost, data.mag_size, data.interval_ms, data.damage], _select_weapon.bind(id))
		button.custom_minimum_size = Vector2(266, 150)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = locked
		row.add_child(button)
		weapon_buttons[id] = button
	shop_armor = CheckBox.new()
	shop_armor.text = "购买护甲  +100 耐久 / $1000（先扣护甲，再扣生命）"
	shop_armor.button_pressed = armor_value > 0
	shop_armor.disabled = locked
	shop_armor.custom_minimum_size.y = 42
	shop_armor.toggled.connect(func(_value): _update_purchase_preview())
	column.add_child(shop_armor)
	shop_money = _label("", 20, AMBER)
	column.add_child(shop_money)
	shop_confirm = _button("确认装备并进入场地", func(): purchase_requested.emit(selected_weapon, shop_armor.button_pressed))
	shop_confirm.disabled = locked
	column.add_child(shop_confirm)
	column.add_child(_button("返回场地  ·  B 可重新查看装备", func(): shop_closed.emit()))
	column.add_child(_label("每回合只能确认一次。未确认则保留免费沙鹰。\n左侧装置：靠近后按 E 测试护甲；准备阶段不能开火。", 16, MUTED))
	_update_purchase_preview()
	if locked:
		shop_money.text = "装备已确认  /  剩余资金 $%d" % money

func _select_weapon(id: String) -> void:
	selected_weapon = id
	_update_purchase_preview()

func _update_purchase_preview() -> void:
	for id in weapon_buttons:
		weapon_buttons[id].modulate = ACCENT if id == selected_weapon else Color.WHITE
	if not shop_locked:
		var price: int = 0 if selected_weapon == "deagle" else Rules.WEAPONS[selected_weapon].price
		if shop_armor.button_pressed:
			price += 1000
		shop_money.text = "本次支出 $%d  /  剩余资金 $%d" % [price, 5000 - price]

func hide_overlay() -> void:
	overlay.hide()
	overlay_kind = ""
	hud.show()

func show_pause() -> void:
	var column := _clear_overlay("pause")
	column.add_child(_label("PAUSED / 训练已暂停", 17, ACCENT))
	column.add_child(_label("停一下，找回节奏。", 36))
	column.add_child(_label("回合、换弹、射击冷却与靶子计时均已冻结。", 20, MUTED))
	column.add_child(_button("继续  /  Esc", func(): resume_requested.emit()))
	column.add_child(_button("返回主菜单", func(): menu_requested.emit()))

func show_results(data: Dictionary) -> void:
	hud.hide()
	var column := _clear_overlay("results")
	column.add_child(_label("SESSION COMPLETE / 本轮完成", 17, ACCENT))
	column.add_child(_label("每次停稳，都是进步。", 36))
	column.add_child(_label(data.reason, 20, AMBER))
	column.add_child(HSeparator.new())
	column.add_child(_label("%02d 击杀       %.1f%% 命中率       %.1f%% 爆头率" % [data.kills, data.accuracy, data.headshot_rate], 29))
	column.add_child(_label("实际发射 %d 发   /   命中 %d 发   /   爆头击杀 %d\n使用武器：%s" % [data.shots, data.hits, data.headshots, data.weapon], 20, MUTED))
	column.add_child(_button("再练一轮  →", func(): start_requested.emit()))
	column.add_child(_button("返回主菜单", func(): menu_requested.emit()))

func update_status(data: Dictionary) -> void:
	if overlay_kind == "buy" and is_instance_valid(shop_countdown):
		shop_countdown.text = "01 / 装备准备     ·     %.1f 秒后自动开始训练" % data.remaining
	heading.text = "RM / 准备阶段" if data.phase == "buy" else "RM / 急停训练"
	clock_label.text = "%04.1f s" % maxf(0.0, data.remaining)
	scores.text = "击杀  %d     命中率  %.1f%%" % [data.kills, data.accuracy]
	ammo.text = "%s  %02d / %02d" % [data.weapon, data.mag, data.reserve]
	vitals.text = "生命 %d     护甲 %d" % [data.hp, data.armor]
	velocity_label.text = "速度比  %.3f / 0.340" % data.speed
	speed_bar.value = data.speed
	permit_label.text = data.permission
	permit_label.add_theme_color_override("font_color", ACCENT if data.ready else AMBER)
	crosshair.add_theme_color_override("font_color", ACCENT if data.ready else AMBER)
	instructions.text = "WASD 移动 · B 装备 · E 测试装置 · Esc 暂停" if data.phase == "buy" else "WASD 移动 · 左键单发 · R 换弹 · Esc 暂停"

func notify(message: String, duration: float = 2.0) -> void:
	toast.text = message
	toast_left = duration

func show_hit(headshot: bool, killed: bool) -> void:
	hit_marker.text = "×"
	hit_marker.add_theme_color_override("font_color", AMBER if headshot else ACCENT)
	hit_marker.show()
	marker_left = 0.18
	if killed:
		notify("爆头击杀" if headshot else "靶子击倒", 0.8)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	toast_left = maxf(0.0, toast_left - delta)
	marker_left = maxf(0.0, marker_left - delta)
	if toast_left <= 0.0:
		toast.text = ""
	if marker_left <= 0.0:
		hit_marker.hide()
