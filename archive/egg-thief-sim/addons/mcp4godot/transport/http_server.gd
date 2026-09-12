@tool
class_name MCPHTTPServer
extends Node
## MCP 服务器的流式 HTTP 传输层。
##
## 使用 Godot 的 [TCPServer] 实现 MCP Streamable HTTP 传输规范。
## 处理客户端的 POST/GET/DELETE/OPTIONS 请求，支持 SSE 服务器推送。
##
## 参考: [url]https://modelcontextprotocol.org/specification/2025-03-26/basic/transports[/url]

## 服务器状态变化时发出。[param status] 为状态描述字符串。
signal status_changed(status: String)

## 收到请求或发生事件时发出，用于日志记录。[param message] 为日志内容。
signal log_message(message: String)

## 新会话创建时发出。[param event] 包含 [code]session_id[/code] 和 [code]timestamp[/code]。
signal session_created(event: Dictionary)

var _tcp_server: TCPServer
var _is_running: bool = false
var _port: int = 0

## 连接数据缓冲区。键为连接 ID，值为字典 [code]{ stream, buffer, is_sse }[/code]。
var _connections: Dictionary = {}

## 下一个连接 ID 的计数器，自增分配。
var _next_conn_id: int = 1

## MCP 消息处理器。由 [MCPHandler] 设置，负责解析和路由 JSON-RPC 消息。
var mcp_handler: MCPHandler

## 活跃会话表。键为会话 ID，值为会话数据字典。
var _sessions: Dictionary = {}

## SSE 流注册表。键为会话 ID，值为该会话下的连接 ID 数组。
var _sse_streams: Dictionary = {}

## 连接与会话的映射表。键为连接 ID，值为会话 ID。
var _conn_to_session: Dictionary = {}


## 启动 HTTP 服务器。
##
## 在指定端口监听 TCP 连接。如果服务器已在运行，会先停止再重新启动。
## [param port] 为监听的端口号。
## 启动成功返回 [code]true[/code]，失败返回 [code]false[/code] 并触发 [signal status_changed]。
func start_server(port: int) -> bool:
	if _is_running:
		stop_server()

	_tcp_server = TCPServer.new()
	# MCP grants editor and project access, so never expose it to the LAN.
	var err: int = _tcp_server.listen(port, "127.0.0.1")
	if err != OK:
		push_error(tr("START_FAILED_ERROR") % [port, error_string(err)])
		_tcp_server = null
		status_changed.emit(tr("STATUS_START_FAILED") % port)
		return false

	_port = port
	_is_running = true
	status_changed.emit(tr("STATUS_RUNNING") % port)
	return true


## 停止 HTTP 服务器。
##
## 断开所有连接，清空会话和 SSE 流，释放端口。触发 [signal status_changed]。
func stop_server() -> void:
	for conn_id in _connections.keys():
		_disconnect(conn_id)
	_connections.clear()
	_sessions.clear()
	_sse_streams.clear()
	_conn_to_session.clear()
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null
	_is_running = false
	_port = 0
	status_changed.emit(tr("STATUS_STOPPED"))


## 返回服务器是否正在运行。
func is_running() -> bool:
	return _is_running


## 返回当前监听的端口号。未启动时返回 [code]0[/code]。
func get_port() -> int:
	return _port


## 每帧处理新连接和已有连接的数据。
##
## 在 [method _process] 中完成：
## - 接受新的 TCP 连接
## - 读取每个连接的数据到缓冲区
## - 尝试解析完整的 HTTP 请求
## - 清理已断开或出错的连接
func _process(_delta: float) -> void:
	if not _is_running or not _tcp_server:
		return

	# 接受新的 TCP 连接
	while _tcp_server.is_connection_available():
		var stream: StreamPeerTCP = _tcp_server.take_connection()
		var conn_id: int = _next_conn_id
		_next_conn_id += 1
		_connections[conn_id] = {
			"stream": stream,
			"buffer": PackedByteArray(),
			"is_sse": false,
		}

	# 处理每个连接
	var to_remove: Array[int] = []
	for conn_id in _connections.keys():
		var conn: Dictionary = _connections[conn_id]
		var stream: StreamPeerTCP = conn["stream"]
		var status: int = stream.get_status()

		if status == StreamPeerTCP.STATUS_CONNECTED:
			# SSE 连接是长连接，跳过处理
			if conn["is_sse"]:
				continue

			var available: int = stream.get_available_bytes()
			if available > 0:
				var result: Array = stream.get_partial_data(available)
				# get_partial_data 返回 [错误码, PackedByteArray]
				if result[0] == OK and result[1].size() > 0:
					var chunk: PackedByteArray = result[1]
					conn["buffer"].append_array(chunk)
					_try_process_request(conn_id)
		elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
			to_remove.append(conn_id)

	for conn_id in to_remove:
		_disconnect(conn_id)


## 尝试从缓冲区解析并处理一个完整的 HTTP 请求。
##
## 检查缓冲区中是否有完整的请求头（以 [code]\r\n\r\n[/code] 结尾）和完整的请求体（满足 Content-Length）。
## 解析完成后按 HTTP 方法分发给对应的处理函数。
## [param conn_id] 为连接 ID，用于从 [member _connections] 中读取缓冲区和流。
func _try_process_request(conn_id: int) -> void:
	var conn: Dictionary = _connections[conn_id]
	var buffer: PackedByteArray = conn["buffer"]
	var raw: String = buffer.get_string_from_utf8()

	# 检查是否收到完整的请求头 (以 \r\n\r\n 结尾)
	var header_end: int = raw.find("\r\n\r\n")
	if header_end < 0:
		return  # 请求头尚未完整，等待更多数据

	# 解析请求头以检查 Content-Length
	var header_section: String = raw.substr(0, header_end)
	var headers: Dictionary = _parse_headers(header_section)
	var content_length: int = int(headers.get("content-length", "0"))

	# 检查请求体是否完整
	var body_start: int = header_end + 4
	var body_bytes_received: int = buffer.size() - (header_end + 4)  # 使用字节数

	if body_bytes_received < content_length:
		return  # 请求体尚未完整，等待更多数据

	# 请求已完整 — 提取请求体
	var body: String = raw.substr(body_start, content_length)

	# 从缓冲区移除已处理的请求
	var consumed: int = body_start + content_length
	var remaining: PackedByteArray = buffer.slice(consumed)
	conn["buffer"] = remaining

	# 解析请求行
	var first_line: String = header_section.split("\r\n", false)[0]
	var parts: PackedStringArray = first_line.split(" ", false, 2)
	var method: String = parts[0] if parts.size() > 0 else ""
	var path: String = parts[1] if parts.size() > 1 else "/"

	var session_id: String = headers.get("mcp-session-id", "")

	log_message.emit(tr("LOG_REQUEST") % [method, path, session_id if not session_id.is_empty() else tr("LOG_NEW_SESSION")])

	# 按方法路由
	match method:
		"POST":
			_handle_post(conn_id, conn["stream"], body, session_id, headers)
		"GET":
			_handle_get(conn_id, conn["stream"], session_id, headers)
		"DELETE":
			_handle_delete(conn_id, conn["stream"], session_id)
		"OPTIONS":
			_handle_options(conn["stream"], headers)
		_:
			_send_response(conn["stream"], 405, "Method Not Allowed", {})

	# 如果缓冲区还有剩余数据，尝试处理下一个请求
	if conn["buffer"].size() > 0:
		_try_process_request(conn_id)


## 从请求头字符串解析键值对。
##
## 按 [code]\r\n[/code] 分割，跳过第一行（请求行），提取 [code]Key: Value[/code] 格式。
## [param header_section] 为请求头文本（不含请求体）。
## 返回字典，键为小写的请求头名称。
func _parse_headers(header_section: String) -> Dictionary:
	var headers: Dictionary = {}
	var lines: PackedStringArray = header_section.split("\r\n", false)
	for i in range(1, lines.size()):  # 跳过请求行
		var line: String = lines[i]
		var colon_pos: int = line.find(": ")
		if colon_pos > 0:
			var key: String = line.substr(0, colon_pos).to_lower()
			var value: String = line.substr(colon_pos + 2)
			headers[key] = value
	return headers


## 处理 POST 请求。
##
## 客户端通过 POST 发送 JSON-RPC 消息。如果请求是 [code]initialize[/code] 且没有会话，
## 则创建新会话。消息通过 [member mcp_handler] 同步处理。
## [param conn_id] 为连接 ID。
## [param stream] 为 TCP 流，用于发送响应。
## [param body] 为请求体中的 JSON-RPC 消息。
## [param session_id] 为当前会话 ID（可能为空）。
## [param headers] 为请求头字典。
func _handle_post(conn_id: int, stream: StreamPeerTCP, body: String, session_id: String, headers: Dictionary) -> void:
	if body.strip_edges().is_empty():
		_send_response(stream, 400, "Bad Request", {}, tr("ERR_MISSING_BODY"))
		return

	if mcp_handler == null:
		_send_response(stream, 500, "Internal Server Error", {}, tr("ERR_HANDLER_NOT_SET"))
		return

	# 如果是初始化请求且没有会话，则创建会话
	if session_id.is_empty() and _is_initialize_request(body):
		session_id = _generate_session_id()
		_sessions[session_id] = {}
		mcp_handler.on_client_connected(session_id)
		session_created.emit({
			"session_id": session_id,
			"timestamp": Time.get_time_string_from_system(),
		})

	# 为此连接注册会话
	if not session_id.is_empty() and not _conn_to_session.has(conn_id):
		_conn_to_session[conn_id] = session_id

	# 通过 MCPHandler 同步处理消息
	var response_json: String = mcp_handler.process_message(session_id, body)

	# 如果请求体只包含通知/响应 (没有 id) → 返回 202 Accepted
	if not _contains_request(body):
		_send_response(stream, 202, "Accepted", {})
		return

	# 返回 JSON-RPC 响应
	var resp_headers: Dictionary = {
		"Content-Type": "application/json",
	}
	if not session_id.is_empty():
		resp_headers["Mcp-Session-Id"] = session_id

	_send_response(stream, 200, "OK", resp_headers, response_json)


## 处理 GET 请求，建立 SSE 流。
##
## 客户端通过 GET 请求打开 Server-Sent Events 流，用于接收服务器推送。
## 连接被标记为 SSE 长连接，不再处理普通 HTTP 请求。
## [param conn_id] 为连接 ID。
## [param stream] 为 TCP 流，用于发送 SSE 响应头。
## [param session_id] 为当前会话 ID。
## [param headers] 为请求头字典，检查 Accept 是否包含 [code]text/event-stream[/code]。
func _handle_get(conn_id: int, stream: StreamPeerTCP, session_id: String, headers: Dictionary) -> void:
	var accept: String = headers.get("accept", "")
	if not accept.contains("text/event-stream"):
		_send_response(stream, 400, "Bad Request", {}, tr("ERR_ACCEPT_HEADER"))
		return

	# 发送 SSE 流响应头
	var resp_headers: Dictionary = {
		"Content-Type": "text/event-stream",
		"Cache-Control": "no-cache",
		"Connection": "keep-alive",
	}
	if not session_id.is_empty():
		resp_headers["Mcp-Session-Id"] = session_id

	_send_raw_response(stream, 200, "OK", resp_headers, "")

	# 将此连接标记为 SSE 流
	_connections[conn_id]["is_sse"] = true

	# 注册为 SSE 流
	if not session_id.is_empty():
		if not _sse_streams.has(session_id):
			_sse_streams[session_id] = []
		_sse_streams[session_id].append(conn_id)
		_conn_to_session[conn_id] = session_id


## 处理 DELETE 请求，终止会话。
##
## 断开该会话下的所有 SSE 连接，清理会话数据，通知 [member mcp_handler]。
## [param conn_id] 为连接 ID。
## [param stream] 为 TCP 流，用于发送响应。
## [param session_id] 为要终止的会话 ID。
func _handle_delete(conn_id: int, stream: StreamPeerTCP, session_id: String) -> void:
	if session_id.is_empty():
		_send_response(stream, 400, "Bad Request", {}, tr("ERR_MISSING_SESSION"))
		return

	if _sessions.has(session_id):
		if _sse_streams.has(session_id):
			for sse_conn_id in _sse_streams[session_id]:
				_disconnect(sse_conn_id)
			_sse_streams.erase(session_id)

		mcp_handler.on_client_disconnected(session_id)
		_sessions.erase(session_id)
		_send_response(stream, 200, "OK", {})
	else:
		_send_response(stream, 404, "Not Found", {})


## 处理 OPTIONS 请求，响应 CORS 预检。
##
## 返回允许的源、方法和请求头，支持跨域访问。
## [param stream] 为 TCP 流，用于发送响应。
## [param _headers] 为请求头字典（未使用）。
func _handle_options(stream: StreamPeerTCP, _headers: Dictionary) -> void:
	var resp_headers: Dictionary = {
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id",
		"Access-Control-Max-Age": "86400",
	}
	_send_raw_response(stream, 204, "No Content", resp_headers, "")


## 发送标准 HTTP 响应（自动附加 CORS 请求头和 Content-Length）。
## [param stream] 为 TCP 流。
## [param code] 为 HTTP 状态码。
## [param reason] 为 HTTP 状态文本。
## [param extra_headers] 为额外的响应头字典。
## [param body] 为响应体文本。
func _send_response(stream: StreamPeerTCP, code: int, reason: String, extra_headers: Dictionary = {}, body: String = "") -> void:
	var headers: Dictionary = {
		"Content-Type": "application/json",
		"Access-Control-Allow-Origin": "*",
	}
	headers.merge(extra_headers)

	if not body.is_empty():
		headers["Content-Length"] = str(body.to_utf8_buffer().size())
	else:
		headers["Content-Length"] = "0"

	_send_raw_response(stream, code, reason, headers, body)


## 发送原始 HTTP 响应。
##
## 按 HTTP/1.1 格式构造响应行、请求头和请求体，写入 TCP 流。
## [param stream] 为 TCP 流。
## [param code] 为 HTTP 状态码。
## [param reason] 为 HTTP 状态文本。
## [param headers] 为响应头字典。
## [param body] 为响应体文本。
func _send_raw_response(stream: StreamPeerTCP, code: int, reason: String, headers: Dictionary, body: String) -> void:
	var response: String = "HTTP/1.1 %d %s\r\n" % [code, reason]
	for key in headers:
		response += "%s: %s\r\n" % [key, str(headers[key])]
	response += "\r\n"
	if not body.is_empty():
		response += body
	stream.put_data(response.to_utf8_buffer())


## 向指定会话的所有 SSE 连接推送事件。
##
## 遍历该会话注册的 SSE 连接，发送 [code]data: ...\r\n\r\n[/code] 格式的事件数据。
## [param session_id] 为目标会话 ID。
## [param data] 为要推送的 JSON 字符串。
func send_sse_event(session_id: String, data: String) -> void:
	if not _sse_streams.has(session_id):
		return
	for conn_id in _sse_streams[session_id]:
		if _connections.has(conn_id):
			var conn: Dictionary = _connections[conn_id]
			var stream: StreamPeerTCP = conn["stream"]
			if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				var event: String = "data: %s\r\n\r\n" % data
				stream.put_data(event.to_utf8_buffer())


## 断开指定连接并清理相关数据。
##
## 关闭 TCP 流，从 [member _connections] 移除，
## 同时清理 [member _sse_streams] 和 [member _conn_to_session] 中的关联。
## [param conn_id] 为要断开的连接 ID。
func _disconnect(conn_id: int) -> void:
	if _connections.has(conn_id):
		var conn: Dictionary = _connections[conn_id]
		var stream: StreamPeerTCP = conn["stream"]
		if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			stream.disconnect_peer()
		_connections.erase(conn_id)

	if _conn_to_session.has(conn_id):
		var sid: String = _conn_to_session[conn_id]
		if _sse_streams.has(sid):
			_sse_streams[sid].erase(conn_id)
			if _sse_streams[sid].is_empty():
				_sse_streams.erase(sid)
		_conn_to_session.erase(conn_id)


## 生成唯一会话 ID。
##
## 格式: [code]mcp4godot-{时间戳}-{随机数}[/code]。
func _generate_session_id() -> String:
	return "mcp4godot-%d-%d" % [Time.get_ticks_msec(), randi() % 100000]


## 检查请求体是否包含需要响应的 JSON-RPC 请求。
##
## 判断标准：字典或数组中的元素包含 [code]id[/code] 和 [code]method[/code] 字段。
## 通知（无 id）和响应（无 method）返回 [code]false[/code]。
## [param body] 为 JSON-RPC 请求体。
## 返回 [code]true[/code] 表示包含需要返回 200 OK 的请求。
func _contains_request(body: String) -> bool:
	var json := JSON.new()
	if json.parse(body.strip_edges()) != OK:
		return false
	var data: Variant = json.data

	if data is Array:
		for item in data:
			if item is Dictionary and item.has("id") and item.has("method"):
				return true
		return false

	if data is Dictionary:
		return data.has("id") and data.has("method")

	return false


## 检查请求体是否为 initialize 请求。
##
## [param body] 为 JSON-RPC 请求体。
## 返回 [code]true[/code] 表示是 [code]initialize[/code] 方法请求。
func _is_initialize_request(body: String) -> bool:
	var json := JSON.new()
	if json.parse(body.strip_edges()) != OK:
		return false
	var data: Variant = json.data
	if data is Dictionary:
		return data.get("method", "") == "initialize"
	if data is Array:
		for item in data:
			if item is Dictionary and item.get("method", "") == "initialize":
				return true
	return false


## 节点退出场景树时自动停止服务器。
func _exit_tree() -> void:
	stop_server()
