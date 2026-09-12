@tool
class_name VariantSerializer
extends RefCounted
## Utility class for serializing Godot Variant types to JSON-compatible values
## and deserializing JSON values back to Godot types.


## Serialize a Godot Variant to a JSON-compatible value.
static func serialize(value: Variant) -> Variant:
	if value == null:
		return null

	# Basic types that JSON natively supports
	if value is bool or value is int or value is float or value is String:
		return value

	# StringName and NodePath — serialize as strings
	if value is StringName:
		return str(value)
	if value is NodePath:
		return str(value)

	# Vector types
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Vector3i:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Vector4:
		return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
	if value is Vector4i:
		return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}

	# Color
	if value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}

	# Rect types
	if value is Rect2:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}
	if value is Rect2i:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}

	# AABB
	if value is AABB:
		return {
			"position": {"x": value.position.x, "y": value.position.y, "z": value.position.z},
			"size": {"x": value.size.x, "y": value.size.y, "z": value.size.z},
		}

	# Basis
	if value is Basis:
		return {
			"x": {"x": value.x.x, "y": value.x.y, "z": value.x.z},
			"y": {"x": value.y.x, "y": value.y.y, "z": value.y.z},
			"z": {"x": value.z.x, "y": value.z.y, "z": value.z.z},
		}

	# Transform types
	if value is Transform2D:
		return {
			"x": {"x": value.x.x, "y": value.x.y},
			"y": {"x": value.y.x, "y": value.y.y},
			"origin": {"x": value.origin.x, "y": value.origin.y},
		}
	if value is Transform3D:
		return {
			"basis": {
				"x": {"x": value.basis.x.x, "y": value.basis.x.y, "z": value.basis.x.z},
				"y": {"x": value.basis.y.x, "y": value.basis.y.y, "z": value.basis.y.z},
				"z": {"x": value.basis.z.x, "y": value.basis.z.y, "z": value.basis.z.z},
			},
			"origin": {"x": value.origin.x, "y": value.origin.y, "z": value.origin.z},
		}

	# Projection
	if value is Projection:
		return {
			"x": serialize(value.x),
			"y": serialize(value.y),
			"z": serialize(value.z),
			"w": serialize(value.w),
		}

	# Quaternion
	if value is Quaternion:
		return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}

	# Plane
	if value is Plane:
		return {"x": value.normal.x, "y": value.normal.y, "z": value.normal.z, "d": value.d}

	# RID — descriptive only, cannot be reconstructed
	if value is RID:
		return {"type": "RID", "id": value.get_id()}

	# Callable — descriptive only
	if value is Callable:
		var obj: Object = value.get_object()
		return {
			"type": "Callable",
			"method": value.get_method(),
			"object": obj.get_class() if obj else "null",
		}

	# Collections
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(serialize(item))
		return arr
	if value is Dictionary:
		var dict: Dictionary = {}
		for key in value:
			dict[str(key)] = serialize(value[key])
		return dict

	# Packed arrays
	if value is PackedStringArray:
		return Array(value)
	if value is PackedInt32Array:
		return Array(value)
	if value is PackedInt64Array:
		return Array(value)
	if value is PackedFloat32Array:
		return Array(value)
	if value is PackedFloat64Array:
		return Array(value)
	if value is PackedByteArray:
		return Array(value)
	if value is PackedVector2Array:
		var arr: Array = []
		for v in value:
			arr.append(serialize(v))
		return arr
	if value is PackedVector3Array:
		var arr: Array = []
		for v in value:
			arr.append(serialize(v))
		return arr
	if value is PackedColorArray:
		var arr: Array = []
		for v in value:
			arr.append(serialize(v))
		return arr

	# Node reference — compact form, don't expand all properties
	if value is Node:
		return {"type": value.get_class(), "path": str(value.get_path())}

	# Resource with resource_path — compact form to avoid recursion
	if value is Resource and value.resource_path != null and not value.resource_path.is_empty():
		return {"type": value.get_class(), "resource_path": value.resource_path}

	# Object/Resource (inline) — reflect properties automatically
	if value is Object:
		return _serialize_object_properties(value)

	# Fallback: convert to string
	return str(value)


## Auto-serialize an Object's properties via reflection.
## Uses get_property_list() to extract all storage properties automatically.
static func _serialize_object_properties(obj: Object) -> Dictionary:
	var result: Dictionary = {"type": obj.get_class()}

	for prop in obj.get_property_list():
		var usage: int = prop.get("usage", 0)

		# Skip internal, category, group, subgroup entries
		if usage & 64:    # PROPERTY_USAGE_INTERNAL
			continue
		if usage & 256:   # PROPERTY_USAGE_CATEGORY
			continue
		if usage & 32:    # PROPERTY_USAGE_GROUP
			continue
		if usage & 512:   # PROPERTY_USAGE_SUBGROUP
			continue

		# Only include storage properties (those that Godot itself serializes)
		if not (usage & 2):  # PROPERTY_USAGE_STORAGE
			continue

		var prop_name: String = prop["name"]

		# Skip metadata properties that add no value for LLMs
		if prop_name in ["resource_path", "resource_name", "resource_local_to_scene", "script"]:
			continue

		var prop_value: Variant = obj.get(prop_name)
		result[prop_name] = serialize(prop_value)

	# Add human-readable key name for InputEventKey
	if obj is InputEventKey:
		var key_name: String = OS.get_keycode_string(obj.physical_keycode)
		if key_name.is_empty():
			key_name = OS.get_keycode_string(obj.keycode)
		if not key_name.is_empty():
			result["key"] = key_name

	return result


## Deserialize a JSON value to a Godot Variant for property setting.
## Tries to infer the target type from the property hint when available.
static func deserialize(value: Variant, target_type: int = TYPE_NIL) -> Variant:
	if value == null:
		return null

	# If we know the target type, use it for conversion
	if target_type != TYPE_NIL:
		return _deserialize_typed(value, target_type)

	# Auto-detect from JSON value
	if value is bool:
		return value
	if value is int:
		return value
	if value is float:
		return value
	if value is String:
		return value
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(deserialize(item))
		return arr
	if value is Dictionary:
		# Normalize keys to String for consistent access
		var norm: Dictionary = _normalize_dict_keys(value)
		# Try to detect common Godot types by their keys
		if norm.has("x") and norm.has("y"):
			if norm.has("z"):
				if norm.has("w"):
					return Vector4(float(norm["x"]), float(norm["y"]), float(norm["z"]), float(norm["w"]))
				return Vector3(float(norm["x"]), float(norm["y"]), float(norm["z"]))
			return Vector2(float(norm["x"]), float(norm["y"]))
		if norm.has("r") and norm.has("g") and norm.has("b"):
			var a: float = float(norm.get("a", 1.0))
			return Color(float(norm["r"]), float(norm["g"]), float(norm["b"]), a)
		# AABB detection: has position and size with x/y/z
		if norm.has("position") and norm.has("size"):
			var pos: Dictionary = _normalize_dict_keys(norm["position"]) if norm["position"] is Dictionary else {}
			var sz: Dictionary = _normalize_dict_keys(norm["size"]) if norm["size"] is Dictionary else {}
			if pos.has("x") and pos.has("y") and pos.has("z") and sz.has("x") and sz.has("y") and sz.has("z"):
				return AABB(
					Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"])),
					Vector3(float(sz["x"]), float(sz["y"]), float(sz["z"]))
				)
		# Generic dictionary
		var dict: Dictionary = {}
		for key in value:
			dict[key] = deserialize(value[key])
		return dict

	return value


## Deserialize with a known target type.
static func _deserialize_typed(value: Variant, target_type: int) -> Variant:
	match target_type:
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			return NodePath(str(value))
		TYPE_VECTOR2:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
			return Vector2()
		TYPE_VECTOR2I:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
			return Vector2i()
		TYPE_VECTOR3:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
			return Vector3()
		TYPE_VECTOR3I:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector3i(int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("z", 0)))
			return Vector3i()
		TYPE_VECTOR4:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector4(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)), float(d.get("w", 0)))
			return Vector4()
		TYPE_VECTOR4I:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Vector4i(int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("z", 0)), int(d.get("w", 0)))
			return Vector4i()
		TYPE_COLOR:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Color(
					float(d.get("r", 0)),
					float(d.get("g", 0)),
					float(d.get("b", 0)),
					float(d.get("a", 1.0))
				)
			if value is String:
				return Color(value)
			return Color()
		TYPE_RECT2:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Rect2(
					float(d.get("x", 0)), float(d.get("y", 0)),
					float(d.get("w", 0)), float(d.get("h", 0))
				)
			return Rect2()
		TYPE_RECT2I:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Rect2i(
					int(d.get("x", 0)), int(d.get("y", 0)),
					int(d.get("w", 0)), int(d.get("h", 0))
				)
			return Rect2i()
		TYPE_AABB:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				var pos: Variant = d.get("position", {})
				var sz: Variant = d.get("size", {})
				if pos is Dictionary and sz is Dictionary:
					var pd: Dictionary = _normalize_dict_keys(pos)
					var sd: Dictionary = _normalize_dict_keys(sz)
					return AABB(
						Vector3(float(pd.get("x", 0)), float(pd.get("y", 0)), float(pd.get("z", 0))),
						Vector3(float(sd.get("x", 0)), float(sd.get("y", 0)), float(sd.get("z", 0)))
					)
			return AABB()
		TYPE_BASIS:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Basis(
					Vector3(float(_nested_get(d, "x", "x")), float(_nested_get(d, "x", "y")), float(_nested_get(d, "x", "z"))),
					Vector3(float(_nested_get(d, "y", "x")), float(_nested_get(d, "y", "y")), float(_nested_get(d, "y", "z"))),
					Vector3(float(_nested_get(d, "z", "x")), float(_nested_get(d, "z", "y")), float(_nested_get(d, "z", "z")))
				)
			return Basis()
		TYPE_QUATERNION:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				return Quaternion(
					float(d.get("x", 0)), float(d.get("y", 0)),
					float(d.get("z", 0)), float(d.get("w", 1.0))
				)
			return Quaternion()
		TYPE_TRANSFORM3D:
			if value is Dictionary:
				var d: Dictionary = _normalize_dict_keys(value)
				var basis_dict: Variant = d.get("basis", {})
				var origin_dict: Variant = d.get("origin", {})
				var b: Basis = deserialize(basis_dict, TYPE_BASIS) if basis_dict is Dictionary else Basis()
				var o: Vector3 = deserialize(origin_dict, TYPE_VECTOR3) if origin_dict is Dictionary else Vector3()
				return Transform3D(b, o)
			return Transform3D()
		TYPE_ARRAY:
			if value is Array:
				return value
			return []
		TYPE_DICTIONARY:
			if value is Dictionary:
				return value
			return {}
		TYPE_OBJECT:
			# Resource types (Texture2D, Material, etc.) — load from resource path string
			if value is String and value.begins_with("res://"):
				var res: Resource = load(value)
				if res != null:
					return res
			# Dictionary with resource_path — try to load
			if value is Dictionary:
				var norm: Dictionary = _normalize_dict_keys(value)
				var res_path: String = str(norm.get("resource_path", ""))
				if not res_path.is_empty() and res_path.begins_with("res://"):
					var res: Resource = load(res_path)
					if res != null:
						return res
			return value
		_:
			return value


## Helper: get a nested value from a dict-of-dicts, e.g. _nested_get(d, "x", "y") → d["x"]["y"]
static func _nested_get(d: Dictionary, key1: String, key2: String) -> float:
	var inner: Variant = d.get(key1, {})
	if inner is Dictionary:
		var norm: Dictionary = _normalize_dict_keys(inner)
		return float(norm.get(key2, 0))
	return 0.0


## Get the Godot type number for a type name string.
static func type_from_string(type_name: String) -> int:
	var type_map: Dictionary = {
		"bool": TYPE_BOOL,
		"int": TYPE_INT,
		"float": TYPE_FLOAT,
		"String": TYPE_STRING,
		"StringName": TYPE_STRING_NAME,
		"NodePath": TYPE_NODE_PATH,
		"Vector2": TYPE_VECTOR2,
		"Vector2i": TYPE_VECTOR2I,
		"Vector3": TYPE_VECTOR3,
		"Vector3i": TYPE_VECTOR3I,
		"Vector4": TYPE_VECTOR4,
		"Vector4i": TYPE_VECTOR4I,
		"Color": TYPE_COLOR,
		"Rect2": TYPE_RECT2,
		"Rect2i": TYPE_RECT2I,
		"AABB": TYPE_AABB,
		"Basis": TYPE_BASIS,
		"Quaternion": TYPE_QUATERNION,
		"Transform3D": TYPE_TRANSFORM3D,
		"Array": TYPE_ARRAY,
		"Dictionary": TYPE_DICTIONARY,
	}
	return type_map.get(type_name, TYPE_NIL)


## Normalize dictionary keys to String for consistent access.
## Godot's JSON parser may produce keys as StringName or other Variant types,
## which can cause .get("x") lookups to fail even when the key visually appears as "x".
static func _normalize_dict_keys(dict: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in dict:
		normalized[str(key)] = dict[key]
	return normalized
