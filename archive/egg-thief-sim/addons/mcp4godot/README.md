# MCP4Godot

A native Godot 4.x editor plugin that provides an MCP (Model Context Protocol) server, allowing AI clients like Claude to directly control the Godot editor — no external process needed.

[![Godot 4.2+](https://img.shields.io/badge/Godot-4.2%2B-478CBF?logo=godot-engine)](https://godotengine.org)
[![MCP 2025-03-26](https://img.shields.io/badge/MCP-2025--03--26-green)](https://modelcontextprotocol.io)
[![MIT License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

[中文文档](README.zh-CN.md)

## Why MCP4Godot?

Unlike other Godot MCP solutions that require an external Node.js process, **MCP4Godot runs entirely inside the Godot editor** as a native plugin:

- **Zero external dependencies** — No Node.js, no npm, no separate process to manage
- **Native EditorPlugin** — Full access to Godot's editor APIs from within
- **Streamable HTTP** — MCP standard transport, not the older WebSocket approach
- **Instant startup** — Starts with the editor, no manual launch step
- **38 built-in tools** across 6 categories for complete editor control

## Features

- **MCP Server** — Godot acts as an MCP server that AI clients connect to
- **Streamable HTTP Transport** — Compatible with Claude Code and other MCP clients via `http://localhost:9876/mcp`
- **38 Built-in Tools** across 6 categories:
  - **Node Operations** (8): get, get_children, create, delete, move, rename, script_attach, script_detach
  - **Property/Method Access** (5): property_get, property_set, property_list, method_call, resource_create
  - **Editor Control** (12): scene_open, scene_save, scene_list, scene_get_current, scene_create, project_run, project_stop, refresh_filesystem, project_structure, search_files, get_class_documentation, get_project_info
  - **File System** (8): file_read, file_write, file_delete, file_list, file_exists, file_copy, file_move, folder_create
  - **Script Analysis** (2): read_script_outline, script_validate
  - **Project Settings** (3): project_settings_list, project_settings_get, project_settings_set
- **Internationalization** — Supports English and Chinese UI

## Requirements

- Godot 4.2 or later
- No additional dependencies

## Installation

### From Godot Asset Library

1. Open **Project → Tools → Asset Library** in the Godot editor
2. Search for "MCP4Godot"
3. Click **Install**

### Manual Installation

1. Copy the `addons/mcp4godot/` folder into your project's `res://addons/` directory
2. Go to **Project → Project Settings → Plugins**
3. Enable the **MCP4Godot** plugin
4. A new dock will appear on the right side of the editor

## Usage

1. In the MCP Server dock, click **Start** to begin listening (default port: 9876)
2. Configure your MCP client to connect:

### Claude Code Configuration

Add to your `.claude/settings.json` or MCP configuration:

```json
{
  "mcpServers": {
    "godot": {
      "type": "http",
      "url": "http://localhost:9876/mcp"
    }
  }
}
```

### Claude Desktop Configuration

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "godot": {
      "url": "http://localhost:9876/mcp",
      "type": "http"
    }
  }
}
```

3. Once connected, the AI client can inspect and modify the scene tree, read and write files, control the editor, and more.

## Tool Reference

### Node Operations

| Tool | Description | Read-Only |
|---|---|---|
| `node_get` | Get detailed information about a node by its NodePath | ✅ |
| `node_get_children` | List all children of a node in the scene tree | ✅ |
| `node_create` | Create a new node and add it as a child of the specified parent | ❌ |
| `node_delete` | Remove and free a node from the scene tree | ❌ |
| `node_move` | Move a node from its current parent to a new parent (reparent) | ❌ |
| `node_rename` | Rename a node in the scene tree | ❌ |
| `script_attach` | Attach a script to a node | ❌ |
| `script_detach` | Detach the script from a node | ❌ |

### Property & Method Access

| Tool | Description | Read-Only |
|---|---|---|
| `property_get` | Get the value of a property on a node | ✅ |
| `property_set` | Set the value of a property on a node | ❌ |
| `property_list` | List all properties of a node with current values and types | ✅ |
| `method_call` | Call a method on a node with the given arguments | ✅ |
| `resource_create` | Create a new resource and assign it to a node property | ❌ |

### Editor Control

| Tool | Description | Read-Only |
|---|---|---|
| `scene_open` | Open a scene file in the editor | ❌ |
| `scene_save` | Save the currently active scene | ❌ |
| `scene_list` | List all currently open scenes | ✅ |
| `scene_get_current` | Get information about the currently edited scene's root node | ✅ |
| `scene_create` | Create a new scene file and open it in the editor | ❌ |
| `project_run` | Run the current project | ❌ |
| `project_stop` | Stop the currently running project | ❌ |
| `refresh_filesystem` | Refresh the editor's filesystem (call after external file changes) | ❌ |
| `project_structure` | Get the project's file and directory structure | ✅ |
| `search_files` | Search for text patterns across project files (supports regex) | ✅ |
| `get_class_documentation` | Get documentation for a Godot built-in class | ✅ |
| `get_project_info` | Get engine version, project settings, and system information | ✅ |

### File System

| Tool | Description | Read-Only |
|---|---|---|
| `file_read` | Read the contents of a file | ✅ |
| `file_write` | Write content to a file, creating it if it doesn't exist | ❌ |
| `file_delete` | Delete a file from the project | ❌ |
| `file_list` | List files and directories at a given path | ✅ |
| `file_exists` | Check whether a file or directory exists | ✅ |
| `file_copy` | Copy a file to a new location | ❌ |
| `file_move` | Move or rename a file | ❌ |
| `folder_create` | Create a new directory (including missing parents) | ❌ |

### Script Analysis

| Tool | Description | Read-Only |
|---|---|---|
| `read_script_outline` | Parse a GDScript file and return its structured outline | ✅ |
| `script_validate` | Validate a GDScript file for syntax and type errors | ✅ |

### Project Settings

| Tool | Description | Read-Only |
|---|---|---|
| `project_settings_list` | List project settings (filterable by prefix and custom status) | ✅ |
| `project_settings_get` | Get the value of a project setting | ✅ |
| `project_settings_set` | Set a project setting value and save to project.godot | ❌ |

## Architecture

```
addons/mcp4godot/
├── plugin.cfg              # Plugin metadata
├── plugin.gd               # EditorPlugin entry point
├── i18n.gd                 # Internationalization helper (TranslationDomain)
├── locales/
│   ├── en.po               # English translations
│   └── zh_CN.po            # Simplified Chinese translations
├── protocol/
│   ├── json_rpc.gd         # JSON-RPC 2.0 parsing/construction
│   ├── mcp_handler.gd      # MCP protocol routing
│   └── mcp_types.gd        # Protocol constants and client state enum
├── tools/
│   ├── mcp_tool.gd         # Base class for all tools
│   ├── tool_registry.gd    # Tool registration and dispatch
│   ├── tool_utils.gd       # Shared utilities (get_node_by_path, etc.)
│   ├── variant_serializer.gd # Godot Variant ↔ JSON conversion
│   ├── node_tools.gd       # 8 node operation tools
│   ├── property_tools.gd   # 5 property/method tools
│   ├── editor_tools.gd     # 12 editor control tools
│   ├── file_tools.gd       # 8 file system tools
│   ├── script_tools.gd     # 2 script analysis tools
│   └── project_settings_tools.gd # 3 project settings tools
├── transport/
│   └── http_server.gd      # Streamable HTTP server (TCPServer-based)
└── ui/
    ├── mcp_dock.tscn       # Dock UI scene
    └── mcp_dock.gd         # Dock logic (start/stop, status, activity cards)
```

## MCP Protocol

The plugin implements MCP protocol version `2025-03-26` with the following capabilities:

- **Tools**: Full support with `listChanged` capability
- **Resources**: Empty (not yet implemented)
- **Prompts**: Empty (not yet implemented)

### Connection Lifecycle

1. Client sends HTTP POST to `/mcp` with `initialize` request
2. Server responds with capabilities and server info
3. Client sends `notifications/initialized` → Connection ready
4. Client sends `tools/list` → Server returns 38 tool definitions
5. Client sends `tools/call` → Server executes tool and returns result

### Session Management

- Sessions are created on `initialize` and tracked via `Mcp-Session-Id` header
- SSE streams are available via GET requests for server-pushed notifications
- Sessions are terminated via DELETE requests

## Internationalization

The plugin supports English and Simplified Chinese, automatically matching the Godot editor's language setting. Translation files use the gettext `.po` format and are located in `addons/mcp4godot/locales/`.

To add a new language:

1. Create a new `.po` file in `addons/mcp4godot/locales/` (e.g., `ja.po`)
2. Add the locale code to `SUPPORTED_LOCALES` in `i18n.gd`
3. Translate all message entries

## Contributing

Bug reports and pull requests are welcome! Areas where contributions are especially helpful:

- Additional translations
- New MCP tool implementations
- Bug fixes and improvements

## License

[MIT License](LICENSE) — Copyright © 2026 MCP4Godot
