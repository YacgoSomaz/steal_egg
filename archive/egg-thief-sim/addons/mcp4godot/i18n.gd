@tool
class_name MCPI18n
extends RefCounted
## Internationalization helper for the MCP4Godot plugin.
## Manages a [TranslationDomain] for plugin-specific translations,
## keeping the plugin's translations isolated from the main Godot domain.
##
## Usage: After calling [method setup], call [method set_translation_domain]
## on any node that needs to use [method @GlobalScope.tr] with this domain.
## Then use the standard [method @GlobalScope.tr] function as usual - it will
## automatically look up translations in this domain.

const PLUGIN_DOMAIN := "mcp4godot"
const LOCALES_DIR := "res://addons/mcp4godot/locales/"
const SUPPORTED_LOCALES := ["en", "zh_CN"]

var _domain: TranslationDomain
var _translations: Array[Translation] = []


## Create the translation domain and load all locale files.
func setup() -> void:
	_domain = TranslationServer.get_or_add_domain(PLUGIN_DOMAIN)
	_load_translations()


## Remove all translations and the domain. Call in [method _exit_tree].
func cleanup() -> void:
	for t in _translations:
		_domain.remove_translation(t)
	_translations.clear()
	TranslationServer.remove_domain(PLUGIN_DOMAIN)


## Returns the plugin's translation domain name, for use with [method Object.set_translation_domain].
static func get_domain_name() -> StringName:
	return &"mcp4godot"


func _load_translations() -> void:
	for locale in SUPPORTED_LOCALES:
		var path: String = LOCALES_DIR + locale + ".po"
		if ResourceLoader.exists(path):
			var translation: Translation = load(path)
			if translation:
				_domain.add_translation(translation)
				_translations.append(translation)
