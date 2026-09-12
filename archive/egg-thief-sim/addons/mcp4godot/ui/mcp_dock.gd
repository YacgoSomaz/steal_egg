@tool
extends VBoxContainer
## MCP Server dock UI.
## Provides controls for starting/stopping the HTTP server and displays
## status, text logs, and interactive activity cards for client events.

signal start_requested(port: int)
signal stop_requested()

## Card styling colors.
const COLOR_CONNECT := Color(0.30, 0.75, 0.40)
const COLOR_DISCONNECT := Color(0.85, 0.35, 0.35)
const COLOR_INIT := Color(0.35, 0.65, 0.90)
const COLOR_READY := Color(0.30, 0.75, 0.40)
const COLOR_TOOL := Color(0.55, 0.45, 0.85)
const COLOR_TOOL_ERROR := Color(0.85, 0.35, 0.35)
const COLOR_SESSION := Color(0.60, 0.60, 0.60)
const COLOR_TIMESTAMP := Color(0.55, 0.55, 0.55)

const COLOR_BG_CLIENT := Color(0.18, 0.22, 0.18, 0.6)
const COLOR_BG_TOOL := Color(0.20, 0.18, 0.25, 0.6)
const COLOR_BG_TOOL_ERROR := Color(0.25, 0.15, 0.15, 0.6)
const COLOR_BG_SESSION := Color(0.18, 0.18, 0.20, 0.6)

const MAX_CARDS := 100
const COLLAPSED_LINES := 20  ## Max visible lines when collapsed

@onready var _port_spin: SpinBox = $PortBox/PortSpin
@onready var _start_button: Button = $ButtonBox/StartButton
@onready var _stop_button: Button = $ButtonBox/StopButton
@onready var _status_label: Label = $StatusLabel
@onready var _header_label: Label = $Header
@onready var _port_label: Label = $PortBox/PortLabel
@onready var _tab_container: TabContainer = $TabContainer
@onready var _log_output: RichTextLabel = $TabContainer/LogTab/LogOutput
@onready var _activity_scroll: ScrollContainer = $TabContainer/ActivityTab/ActivityScroll
@onready var _activity_cards: VBoxContainer = $TabContainer/ActivityTab/ActivityScroll/ActivityCards


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_stop_button.pressed.connect(_on_stop_pressed)
	_apply_translations()


func _on_start_pressed() -> void:
	var port: int = int(_port_spin.value)
	start_requested.emit(port)
	_start_button.disabled = true
	_stop_button.disabled = false
	_port_spin.editable = false


func _on_stop_pressed() -> void:
	stop_requested.emit()
	_start_button.disabled = false
	_stop_button.disabled = true
	_port_spin.editable = true


func set_server_running(port: int) -> void:
	_port_spin.value = port
	_start_button.disabled = true
	_stop_button.disabled = false
	_port_spin.editable = false


## Apply translated strings to UI elements.
func _apply_translations() -> void:
	_header_label.text = tr("DOCK_TITLE")
	_port_label.text = tr("PORT_LABEL")
	_start_button.text = tr("START")
	_stop_button.text = tr("STOP")
	_status_label.text = tr("STATUS_STOPPED")
	# Tab names — find tab indices by metadata
	for i in range(_tab_container.get_tab_count()):
		var tab_control: Control = _tab_container.get_tab_control(i)
		var tab_index: int = tab_control.get_index()
		if tab_control.name == "LogTab":
			_tab_container.set_tab_title(tab_index, tr("TAB_LOG"))
		elif tab_control.name == "ActivityTab":
			_tab_container.set_tab_title(tab_index, tr("TAB_ACTIVITY"))


## Called when the server status changes.
func on_status_changed(status: String) -> void:
	_status_label.text = status


## Called when a generic log message should be displayed.
func on_log_message(message: String) -> void:
	_append_log("[color=#%s][%s][/color] %s" % [
		COLOR_TIMESTAMP.to_html(false),
		Time.get_time_string_from_system(),
		_escape_bbcode(message),
	])


## Called when a client connects.
func on_client_connected(event: Dictionary) -> void:
	var ts: String = event.get("timestamp", "")
	var session: String = event.get("session_key", "")
	var bbcode := "[color=#%s]%s[/color] [b]%s[/b]\n%s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("CLIENT_CONNECTED"), _escape_bbcode(session),
	]
	_create_card(bbcode, COLOR_CONNECT, COLOR_BG_CLIENT)
	_append_log("[color=#%s][%s][/color] %s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("LOG_CLIENT_CONNECTED") % _escape_bbcode(session),
	])


## Called when a client disconnects.
func on_client_disconnected(event: Dictionary) -> void:
	var ts: String = event.get("timestamp", "")
	var session: String = event.get("session_key", "")
	var bbcode := "[color=#%s]%s[/color] [b]%s[/b]\n%s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("CLIENT_DISCONNECTED"), _escape_bbcode(session),
	]
	_create_card(bbcode, COLOR_DISCONNECT, COLOR_BG_CLIENT)
	_append_log("[color=#%s][%s][/color] %s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("LOG_CLIENT_DISCONNECTED") % _escape_bbcode(session),
	])


## Called during the MCP initialize/initialized handshake.
func on_client_initialized(event: Dictionary) -> void:
	var ts: String = event.get("timestamp", "")
	var session: String = event.get("session_key", "")
	var client_name: String = event.get("client_name", "unknown")
	var client_version: String = event.get("client_version", "?")
	var state: String = event.get("state", "initializing")

	var is_ready := (state == "ready")
	var title := tr("CLIENT_READY") if is_ready else tr("CLIENT_INITIALIZING")
	var accent := COLOR_READY if is_ready else COLOR_INIT

	var bbcode := "[color=#%s]%s[/color] [b]%s[/b]\n" % [
		COLOR_TIMESTAMP.to_html(false), ts, title,
	]
	bbcode += "%s [b]%s[/b] v%s\n" % [
		tr("LABEL_CLIENT"), _escape_bbcode(client_name), _escape_bbcode(client_version),
	]
	bbcode += "%s %s" % [tr("LABEL_SESSION"), _escape_bbcode(session)]
	if is_ready:
		bbcode += "\n[color=#%s]%s[/color]" % [COLOR_READY.to_html(false), tr("STATUS_READY")]

	_create_card(bbcode, accent, COLOR_BG_CLIENT)
	_append_log("[color=#%s][%s][/color] %s: %s (%s v%s)" % [
		COLOR_TIMESTAMP.to_html(false), ts, title,
		_escape_bbcode(session), _escape_bbcode(client_name), _escape_bbcode(client_version),
	])


## Called after a tool is executed.
func on_tool_called(event: Dictionary) -> void:
	var ts: String = event.get("timestamp", "")
	var tool_name: String = event.get("tool_name", "")
	var arguments: Variant = event.get("arguments", {})
	var result: Dictionary = event.get("result", {})
	var is_error: bool = event.get("is_error", false)

	var accent := COLOR_TOOL_ERROR if is_error else COLOR_TOOL
	var bg := COLOR_BG_TOOL_ERROR if is_error else COLOR_BG_TOOL

	# Build card BBCode
	var bbcode := "[color=#%s]%s[/color] " % [COLOR_TIMESTAMP.to_html(false), ts]
	if is_error:
		bbcode += "[b][color=#%s]%s %s[/color][/b]\n" % [
			COLOR_TOOL_ERROR.to_html(false), tr("TOOL_ERROR"), _escape_bbcode(tool_name),
		]
	else:
		bbcode += "[b]%s %s[/b]\n" % [tr("TOOL_CALL"), _escape_bbcode(tool_name)]

	# Arguments section — [code] block handles escaping internally
	var args_text: String = JSON.stringify(arguments, "\t") if arguments is Dictionary else str(arguments)
	bbcode += "[color=#%s]%s[/color]\n" % [COLOR_TIMESTAMP.to_html(false), tr("LABEL_INPUT")]
	bbcode += "[code]%s[/code]\n" % _escape_for_code(args_text)

	# Result section — [code] block handles escaping internally
	var result_text := _extract_result_text(result)
	if is_error:
		bbcode += "[color=#%s]%s[/color]\n" % [COLOR_TOOL_ERROR.to_html(false), tr("LABEL_ERROR")]
	else:
		bbcode += "[color=#%s]%s[/color]\n" % [COLOR_TIMESTAMP.to_html(false), tr("LABEL_RESULT")]
	bbcode += "[code]%s[/code]" % _escape_for_code(result_text)

	_create_card(bbcode, accent, bg)

	# Short text log entry
	var log_status := "ERROR" if is_error else "OK"
	_append_log("[color=#%s][%s][/color] Tool: %s (%s)" % [
		COLOR_TIMESTAMP.to_html(false), ts, _escape_bbcode(tool_name), log_status,
	])


## Called when a new MCP session is created.
func on_session_created(event: Dictionary) -> void:
	var ts: String = event.get("timestamp", "")
	var session_id: String = event.get("session_id", "")
	var bbcode := "[color=#%s]%s[/color] [b]%s[/b]\n%s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("NEW_SESSION"), _escape_bbcode(session_id),
	]
	_create_card(bbcode, COLOR_SESSION, COLOR_BG_SESSION)
	_append_log("[color=#%s][%s][/color] %s: %s" % [
		COLOR_TIMESTAMP.to_html(false), ts, tr("NEW_SESSION"), _escape_bbcode(session_id),
	])


## Count the number of newline characters in text (approximate line count).
func _count_lines(text: String) -> int:
	var count := 1
	for c in text:
		if c == '\n':
			count += 1
	return count


## Create a styled activity card with expand/collapse support.
## Uses line count to decide if content should be collapsed at creation time.
## No signals or deferred calls — everything is decided upfront.
func _create_card(bbcode_text: String, accent_color: Color, bg_color: Color) -> PanelContainer:
	var card := PanelContainer.new()

	# Card background and border styling
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = accent_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)

	# Inner layout: content + expand button
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)

	# Decide if card needs collapse based on line count
	var line_count := _count_lines(bbcode_text)
	var needs_collapse := line_count > COLLAPSED_LINES

	# Card content — always start with fit_content so layout calculates correctly
	var content := RichTextLabel.new()
	content.bbcode_enabled = true
	content.fit_content = true
	content.scroll_active = false
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.text = bbcode_text
	inner.add_child(content)

	if needs_collapse:
		# Add expand button at creation time (avoids add_child in signal callback)
		var expand_btn := Button.new()
		expand_btn.text = tr("EXPAND")
		expand_btn.flat = true
		expand_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expand_btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color.TRANSPARENT
		btn_style.set_content_margin_all(4)
		expand_btn.add_theme_stylebox_override("normal", btn_style)
		expand_btn.add_theme_color_override("font_color", accent_color)
		expand_btn.add_theme_color_override("font_hover_color", accent_color.lightened(0.2))
		expand_btn.set_meta("content", content)
		expand_btn.set_meta("is_expanded", false)
		expand_btn.pressed.connect(_on_expand_toggle.bind(expand_btn))
		inner.add_child(expand_btn)

		# After layout completes via resized signal, switch to collapsed mode.
		# Only modify properties in the callback — no add_child/remove_child.
		content.set_meta("_collapse_refined", false)
		content.resized.connect(_on_content_first_layout.bind(content))

	_activity_cards.add_child(card)

	# Trim old cards to prevent unbounded growth
	_trim_cards()

	# Auto-scroll to the new card after layout update
	_scroll_to_bottom.call_deferred()

	return card


## Called on the first resized after layout completes.
## Refines the collapsed height to match exactly COLLAPSED_LINES of actual rendered text.
func _on_content_first_layout(content: RichTextLabel) -> void:
	if content.get_meta("_collapse_refined", false):
		return
	content.set_meta("_collapse_refined", true)

	# Now that layout is complete, calculate the accurate collapsed height
	var total_lines := content.get_line_count()
	if total_lines <= COLLAPSED_LINES:
		# Content fits after layout — no need for collapse, remove expand button
		content.fit_content = true  # Keep fit_content
		var inner := content.get_parent() as VBoxContainer
		if inner:
			for child in inner.get_children():
				if child is Button and child.has_meta("content"):
					child.queue_free()
		return

	# Calculate accurate per-line height and set collapsed height
	var current_height: float = content.size.y
	var line_height: float = current_height / total_lines
	var collapsed_height: float = line_height * COLLAPSED_LINES

	# Store the collapsed height so expand/collapse toggle uses the same value
	content.set_meta("_collapsed_height", collapsed_height)

	# Switch to collapsed mode — only property changes, no add_child
	content.fit_content = false
	content.custom_minimum_size.y = collapsed_height


## Toggle expand/collapse on a card.
func _on_expand_toggle(button: Button) -> void:
	var content: RichTextLabel = button.get_meta("content")
	var is_expanded: bool = button.get_meta("is_expanded")

	if is_expanded:
		# Collapse: use the same collapsed height calculated at creation
		var collapsed_height: float = content.get_meta("_collapsed_height")
		content.fit_content = false
		content.custom_minimum_size.y = collapsed_height
		button.text = tr("EXPAND")
		button.set_meta("is_expanded", false)
	else:
		# Expand: show full content
		content.custom_minimum_size.y = 0.0
		content.fit_content = true
		button.text = tr("COLLAPSE")
		button.set_meta("is_expanded", true)


## Append a BBCode line to the text log.
func _append_log(bbcode_line: String) -> void:
	if _log_output == null:
		return
	_log_output.append_text(bbcode_line + "\n")


## Extract readable text from an MCP tool result Dictionary.
func _extract_result_text(result: Dictionary) -> String:
	var content: Variant = result.get("content", [])
	if content is Array:
		var texts: PackedStringArray = []
		for item in content:
			if item is Dictionary and item.get("type", "") == "text":
				texts.append(str(item.get("text", "")))
		if not texts.is_empty():
			return "\n".join(texts)
	return JSON.stringify(result, "\t")


## Remove oldest cards when the count exceeds the limit.
func _trim_cards() -> void:
	while _activity_cards.get_child_count() > MAX_CARDS:
		var oldest: Node = _activity_cards.get_child(0)
		oldest.queue_free()


## Scroll the activity tab to the bottom.
func _scroll_to_bottom() -> void:
	if _activity_scroll == null:
		return
	var scrollbar: VScrollBar = _activity_scroll.get_v_scroll_bar()
	scrollbar.value = scrollbar.max_value


## Escape BBCode tags in user-provided text to prevent RichTextLabel parsing issues.
## Used for inline text that is NOT inside a [code] block.
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


## Escape text for use inside a [code] block.
## [code] blocks in RichTextLabel don't parse BBCode tags,
## but we still need to handle the [code] end tag [/code] if it appears in the text.
func _escape_for_code(text: String) -> String:
	# Escape [/code] to prevent premature code block termination
	return text.replace("[/code]", "[lb]/code[rb]")
