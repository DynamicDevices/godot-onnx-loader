## General-purpose inspector for the OnnxLoader dense-float32 tensor API.
##
## The scene owns the application layout. This script generates only the parts
## that depend on a loaded model: named input shapes/value boxes and named output
## shapes/value boxes. Point Model Path at another ONNX file, press Load Model,
## edit its concrete shapes and values, then run or benchmark it.
extends Control

const DEFAULT_MODEL := "res://models/matrix_vector.onnx"
const MAX_VISIBLE_VALUES := 512

@onready var model_path: LineEdit = %ModelPath
@onready var input_tables: VBoxContainer = %InputTables
@onready var output_tables: VBoxContainer = %OutputTables
@onready var metadata_text: TextEdit = %MetadataText
@onready var batch_count: SpinBox = %BatchCount
@onready var timing_label: Label = %TimingLabel
@onready var log_text: TextEdit = %LogText

var loader: OnnxLoader
var input_editors: Dictionary = {}
var output_names := PackedStringArray()


func _ready() -> void:
	model_path.text = DEFAULT_MODEL
	_load_model()
	if "--inspector-smoke" in OS.get_cmdline_user_args():
		_run_once.call_deferred()


func _load_model() -> void:
	loader = OnnxLoader.new()
	if not loader.load_model(model_path.text.strip_edges()):
		_error("Could not load %s" % model_path.text)
		return
	_clear(input_tables)
	_clear(output_tables)
	input_editors.clear()
	output_names.clear()
	for descriptor: Dictionary in loader.get_input_descriptors():
		_add_input_table(descriptor)
	for descriptor: Dictionary in loader.get_output_descriptors():
		output_names.append(descriptor["name"])
		_add_output_contract(descriptor)
	var metadata := loader.get_model_metadata()
	metadata_text.text = JSON.stringify(metadata, "  ") if not metadata.is_empty() else "(no ONNX metadata_props)"
	print("ONNX_INSPECTOR_METADATA ", metadata)
	log_text.text = "Loaded %s\nInputs: %s\nOutputs: %s" % [
		model_path.text,
		loader.get_input_descriptors(),
		loader.get_output_descriptors(),
	]
	timing_label.text = "Model loaded"


func _add_input_table(descriptor: Dictionary) -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 5)
	input_tables.add_child(panel)
	var title := Label.new()
	title.text = "%s   float32   declared shape %s" % [descriptor["name"], descriptor["shape"]]
	title.add_theme_color_override("font_color", Color("38bdf8"))
	panel.add_child(title)
	var shape_row := HBoxContainer.new()
	panel.add_child(shape_row)
	var shape_label := Label.new()
	shape_label.text = "Concrete shape"
	shape_row.add_child(shape_label)
	var shape_edit := LineEdit.new()
	shape_edit.text = _concrete_shape_text(descriptor["shape"])
	shape_edit.custom_minimum_size.x = 160
	shape_row.add_child(shape_edit)
	var apply := Button.new()
	apply.text = "Apply Shape"
	shape_row.add_child(apply)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	input_editors[descriptor["name"]] = {"shape": shape_edit, "grid": grid, "values": []}
	apply.pressed.connect(_rebuild_input_values.bind(descriptor["name"]))
	_rebuild_input_values(descriptor["name"])


func _rebuild_input_values(input_name: String) -> void:
	var editor: Dictionary = input_editors[input_name]
	var shape := _parse_shape(editor["shape"].text)
	var count := _element_count(shape)
	var grid: GridContainer = editor["grid"]
	_clear(grid)
	editor["values"] = []
	if count < 1 or count > MAX_VISIBLE_VALUES:
		var warning := Label.new()
		warning.text = "Shape contains %d values; this educational UI supports 1–%d visible values." % [count, MAX_VISIBLE_VALUES]
		grid.add_child(warning)
		return
	for index in count:
		var label := Label.new()
		label.text = "[%d]" % index
		grid.add_child(label)
		var box := SpinBox.new()
		box.min_value = -1.0e9
		box.max_value = 1.0e9
		box.step = 0.01
		box.custom_minimum_size.x = 115
		grid.add_child(box)
		box.value = float(index + 1)
		editor["values"].append(box)


func _add_output_contract(descriptor: Dictionary) -> void:
	var label := Label.new()
	label.name = descriptor["name"]
	label.text = "%s   float32   declared shape %s   (run model to populate)" % [descriptor["name"], descriptor["shape"]]
	output_tables.add_child(label)


func _run_once() -> void:
	if not _bind_inputs():
		return
	var started := Time.get_ticks_usec()
	if not loader.run(output_names):
		_error(loader.get_last_error())
		return
	var elapsed_us := Time.get_ticks_usec() - started
	_show_outputs()
	timing_label.text = "run(): %.3f ms" % (elapsed_us / 1000.0)


func _benchmark() -> void:
	if not _bind_inputs():
		return
	var calls := int(batch_count.value)
	var started := Time.get_ticks_usec()
	for _index in calls:
		if not loader.run(output_names):
			_error(loader.get_last_error())
			return
	var elapsed_us := Time.get_ticks_usec() - started
	_show_outputs()
	timing_label.text = "%d calls: %.3f ms total, %.3f ms/call" % [calls, elapsed_us / 1000.0, elapsed_us / 1000.0 / calls]


func _bind_inputs() -> bool:
	var lines := PackedStringArray()
	for input_name: String in input_editors:
		var editor: Dictionary = input_editors[input_name]
		var shape := _parse_shape(editor["shape"].text)
		var boxes: Array = editor["values"]
		if boxes.size() != _element_count(shape):
			_error("Apply the concrete shape for input %s before running." % input_name)
			return false
		var values := PackedFloat32Array()
		for box: SpinBox in boxes:
			values.append(box.value)
		if not loader.set_input(input_name, values, shape):
			_error("set_input(%s): %s" % [input_name, loader.get_last_error()])
			return false
		lines.append("IN  %s shape=%s values=%s" % [input_name, shape, values])
		print("ONNX_INSPECTOR_INPUT name=%s shape=%s values=%s" % [input_name, shape, values])
	log_text.text = "\n".join(lines)
	return true


func _show_outputs() -> void:
	_clear(output_tables)
	var lines := PackedStringArray([log_text.text])
	for output_name: String in output_names:
		var shape := loader.get_output_shape(output_name)
		var values := loader.get_output(output_name)
		var panel := VBoxContainer.new()
		output_tables.add_child(panel)
		var title := Label.new()
		title.text = "%s   actual shape %s" % [output_name, shape]
		title.add_theme_color_override("font_color", Color("a3e635"))
		panel.add_child(title)
		var grid := GridContainer.new()
		grid.columns = 4
		panel.add_child(grid)
		for index in mini(values.size(), MAX_VISIBLE_VALUES):
			var label := Label.new()
			label.text = "[%d]" % index
			grid.add_child(label)
			var box := SpinBox.new()
			box.min_value = -1.0e9
			box.max_value = 1.0e9
			box.step = 0.000001
			box.editable = false
			box.custom_minimum_size.x = 115
			grid.add_child(box)
			box.value = values[index]
		lines.append("OUT %s shape=%s values=%s" % [output_name, shape, values])
		print("ONNX_INSPECTOR_OUTPUT name=%s shape=%s values=%s" % [output_name, shape, values])
	log_text.text = "\n".join(lines)


func _parse_shape(text: String) -> PackedInt64Array:
	var shape := PackedInt64Array()
	for token in text.replace("[", " ").replace("]", " ").replace(",", " ").split(" ", false):
		shape.append(int(token))
	return shape


func _concrete_shape_text(shape: PackedInt64Array) -> String:
	var parts := PackedStringArray()
	for dimension in shape:
		parts.append(str(maxi(1, dimension)))
	return ", ".join(parts)


func _element_count(shape: PackedInt64Array) -> int:
	var count := 1
	for dimension in shape:
		if dimension < 1:
			return 0
		count *= dimension
	return count


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.free()


func _error(message: String) -> void:
	log_text.text = "ONNX error: " + message
	timing_label.text = "Error"
	push_error(message)
