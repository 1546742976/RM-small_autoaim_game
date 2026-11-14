extends CanvasLayer
signal setup_requested
signal selection_changed(map_id: String, weapon_id: String)
signal launch_requested
signal replay_requested
signal resume_requested
signal menu_requested
signal quit_requested
const Rules = preload("res://scripts/game_rules.gd")
const Maps = preload("res://scripts/arena.gd")
const Reticle = preload("res://scripts/reticle.gd")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const INK := Color("15181c")
const PANEL := Color("202429")
const LINE := Color("424446")
const TEXT := Color("f2f0ea")
const MUTED := Color("a5a5a1")
const ACCENT := Color("d9ad66")
var root: Control
var overlay: Control
var hud: Control
var clock_label: Label
var ammo: Label
var reload_label: Label
var toast: Label
var crosshair: Control
var countdown: Label
var overlay_kind := ""
var help_origin := "menu"
var toast_left := 0.0
var selected_map := "old_town"
var selected_weapon := "deagle"
var map_buttons: Dictionary = {}
var weapon_buttons: Dictionary = {}
var action_buttons: Dictionary = {}
var transition: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 22
	theme.set_color("font_color","Label",TEXT)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		theme.set_color(state,"Button",TEXT)
	theme.set_color("font_disabled_color","Button",MUTED)
	theme.set_stylebox("normal","Button",_box(PANEL,LINE))
	theme.set_stylebox("hover","Button",_box(Color("303338"),ACCENT))
	theme.set_stylebox("pressed","Button",_box(Color("373027"),ACCENT,2))
	theme.set_stylebox("disabled","Button",_box(INK,LINE))
	theme.set_stylebox("focus","Button",_box(Color.TRANSPARENT,ACCENT,2))
	root.theme = theme
	_build_hud()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

func _box(color: Color, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _label(text: String, size := 22, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _button(text: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	if primary:
		button.add_theme_stylebox_override("normal",_box(ACCENT,ACCENT))
		button.add_theme_stylebox_override("hover",_box(Color("ebc486"),ACCENT))
		button.add_theme_stylebox_override("pressed",_box(Color("b98e4b"),ACCENT))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(state,INK)
	var hover_tween: Array[Tween] = []
	var animate := func(brightness: float):
		if not hover_tween.is_empty() and hover_tween[0].is_valid(): hover_tween[0].kill()
		var tween := button.create_tween()
		hover_tween.assign([tween])
		tween.tween_property(button,"modulate",Color(brightness,brightness,brightness),0.12)
	button.mouse_entered.connect(animate.bind(1.07))
	button.mouse_exited.connect(animate.bind(1.0))
	return button

func _place(node: Control, parent: Control, preset: int, rect: Rect2) -> void:
	parent.add_child(node)
	node.set_anchors_and_offsets_preset(preset)
	node.offset_left = rect.position.x
	node.offset_top = rect.position.y
	node.offset_right = rect.end.x
	node.offset_bottom = rect.end.y

func _build_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(hud)
	clock_label = _label("1:00",32)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.8))
	clock_label.add_theme_constant_override("shadow_offset_y",2)
	_place(clock_label,hud,Control.PRESET_CENTER_TOP,Rect2(-75,24,150,48))
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",_box(Color(0.06,0.07,0.08,0.72)))
	_place(panel,hud,Control.PRESET_BOTTOM_RIGHT,Rect2(-235,-120,203,88))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	ammo = _label("07 / 14",34)
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(ammo)
	reload_label = _label("",18,ACCENT)
	reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(reload_label)
	crosshair = Reticle.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(crosshair,hud,Control.PRESET_CENTER,Rect2(-32,-32,64,64))
	toast = _label("",20,ACCENT)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(toast,hud,Control.PRESET_CENTER,Rect2(-180,44,360,36))

func _clear(kind: String, width := 1040.0) -> VBoxContainer:
	if transition != null and transition.is_valid(): transition.kill()
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	action_buttons.clear()
	overlay_kind = kind
	hud.hide()
	overlay.show()
	overlay.modulate = Color.WHITE
	var shade := ColorRect.new()
	shade.color = Color(0.035,0.043,0.05,0.9 if kind == "setup" else 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.add_theme_constant_override("separation",18)
	center.add_child(column)
	column.modulate.a = 0
	transition = create_tween()
	transition.tween_property(column,"modulate:a",1.0,0.12)
	return column

func _spacer(column: VBoxContainer, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	column.add_child(space)

func _action(column: BoxContainer, id: String, text: String, callback: Callable, primary := false) -> Button:
	var button := _button(text,callback,primary)
	column.add_child(button)
	action_buttons[id] = button
	return button

func _focus(button: Button) -> void:
	_grab_focus.call_deferred(weakref(button))

func _grab_focus(reference: WeakRef) -> void:
	var button = reference.get_ref()
	if is_instance_valid(button) and button.is_inside_tree(): button.grab_focus()

func show_menu() -> void:
	var column := _clear("menu",680)
	column.add_child(_label("RM  /  PRECISION",18,ACCENT))
	column.add_child(_label("急停射击训练",56))
	_spacer(column,34)
	_focus(_action(column,"start","开始训练",func(): setup_requested.emit(),true))
	_action(column,"help","操作说明",show_help)
	_action(column,"quit","退出游戏",func(): quit_requested.emit())

func _card(title: String, texture_path: String, height: float, callback: Callable) -> Button:
	var button := _button("",callback)
	button.toggle_mode = true
	button.custom_minimum_size.y = height
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",10)
	margin.add_theme_constant_override("margin_right",10)
	margin.add_theme_constant_override("margin_top",10)
	margin.add_theme_constant_override("margin_bottom",10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if height > 160 else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(texture_path): image.texture = load(texture_path)
	column.add_child(image)
	var label := _label(title,22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	button.tooltip_text = title
	return button

func show_setup(map_id: String, weapon_id: String) -> void:
	selected_map = map_id
	selected_weapon = weapon_id
	map_buttons.clear()
	weapon_buttons.clear()
	var column := _clear("setup",1088)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("准备训练",36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_action(header,"back","返回",func(): menu_requested.emit())
	column.add_child(_label("选择场景",20,MUTED))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation",16)
	column.add_child(maps)
	for id: String in Maps.MAPS:
		var data: Dictionary = Maps.MAPS[id]
		var button := _card(data.name,data.preview,180,func(): _select(id,selected_weapon))
		maps.add_child(button)
		map_buttons[id] = button
	column.add_child(_label("选择枪械",20,MUTED))
	var guns := HBoxContainer.new()
	guns.add_theme_constant_override("separation",16)
	column.add_child(guns)
	for id: String in Rules.WEAPONS:
		var button := _card(Rules.WEAPONS[id].name,"res://assets/ui/"+id+".png",142,func(): _select(selected_map,id))
		guns.add_child(button)
		weapon_buttons[id] = button
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	var launch := _action(footer,"launch","开始训练   →",func(): launch_requested.emit(),true)
	launch.custom_minimum_size.x = 280
	_update_selection()
	_focus(map_buttons[selected_map])

func _select(map_id: String, weapon_id: String) -> void:
	selected_map = map_id
	selected_weapon = weapon_id
	_update_selection()
	selection_changed.emit(map_id,weapon_id)

func _update_selection() -> void:
	for id in map_buttons: map_buttons[id].set_pressed_no_signal(id == selected_map)
	for id in weapon_buttons: weapon_buttons[id].set_pressed_no_signal(id == selected_weapon)

func show_countdown(value: int) -> void:
	var column := _clear("countdown",200)
	overlay.get_child(0).color = Color(0,0,0,0.15)
	countdown = _label(str(value),96,ACCENT)
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(countdown)

func update_countdown(value: int) -> void:
	if overlay_kind == "countdown": countdown.text = str(maxi(1,value))

func hide_overlay() -> void:
	overlay.hide()
	overlay_kind = ""
	hud.show()
	toast.text = ""
	toast_left = 0
	crosshair.hit_left = 0

func show_pause() -> void:
	var column := _clear("pause",480)
	column.add_child(_label("已暂停",42))
	_spacer(column,16)
	_focus(_action(column,"resume","继续训练",func(): resume_requested.emit(),true))
	_action(column,"help","操作说明",show_help)
	_action(column,"menu","返回主菜单",func(): menu_requested.emit())

func show_help() -> void:
	help_origin = overlay_kind
	var column := _clear("help",680)
	column.add_child(_label("操作说明",36))
	column.add_child(_label("W A S D     移动\n鼠标           瞄准\n左键           单发射击\nR                换弹\nEsc             暂停 / 返回",24))
	column.add_child(_label("停稳后开火。只有头部命中能够击倒目标。",22,ACCENT))
	_focus(_action(column,"back","返回",close_help,true))

func close_help() -> void:
	if help_origin == "pause": show_pause()
	else: show_menu()
	if action_buttons.has("help"): _focus(action_buttons.help)

func show_results(data: Dictionary) -> void:
	var column := _clear("results",720)
	column.add_child(_label("训练完成",42))
	column.add_child(_label(data.reason,22,MUTED))
	_spacer(column,18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",80)
	column.add_child(row)
	for metric in [["击杀",str(data.kills)],["命中率","%.1f%%" % data.accuracy]]:
		var block := VBoxContainer.new()
		row.add_child(block)
		block.add_child(_label(metric[0],22,MUTED))
		block.add_child(_label(metric[1],56,TEXT))
	_spacer(column,18)
	_focus(_action(column,"replay","再练一轮",func(): replay_requested.emit(),true))
	_action(column,"setup","更换配置",func(): setup_requested.emit())

func update_status(data: Dictionary) -> void:
	var seconds := ceili(maxf(0,data.remaining))
	clock_label.text = "%d:%02d" % [seconds/60,seconds%60]
	clock_label.add_theme_color_override("font_color",ACCENT if seconds <= 10 else TEXT)
	ammo.text = "%02d / %02d" % [data.mag,data.reserve]
	reload_label.text = "换弹中" if data.reloading else ""
	crosshair.can_fire = data.ready

func notify(message: String, duration := 0.6) -> void:
	if toast_left > 0: return
	toast.text = message
	toast_left = duration

func show_hit(headshot: bool, _killed: bool) -> void:
	crosshair.show_hit(headshot)

func _process(delta: float) -> void:
	if get_tree().paused: return
	toast_left = maxf(0,toast_left-delta)
	if toast_left <= 0: toast.text = ""
