extends Node
## Godot-hosted lifetime stress: concurrent loaders, replacement, reuse, teardown.

const MODEL := "res://models/matrix_vector.onnx"
const RUNS := 500


func _fail(message: String) -> void:
	push_error("GODOT_ONNX_LIFECYCLE_FAILED " + message)
	get_tree().quit(1)


func _run_once(loader, seed: int) -> bool:
	var matrix := PackedFloat32Array()
	matrix.resize(8)
	for i in matrix.size():
		matrix[i] = float(seed + i) * 0.01
	var vector := PackedFloat32Array([
		float(seed) * 0.02, float(seed + 1) * 0.02, float(seed + 2) * 0.02
	])
	if not loader.set_input("matrix", matrix, PackedInt64Array([4, 2])):
		return false
	if not loader.set_input("vector", vector, PackedInt64Array([3])):
		return false
	if not loader.run(PackedStringArray(["output"])):
		return false
	return loader.get_output("output").size() == 2


func _ready() -> void:
	var first = ClassDB.instantiate("OnnxLoader")
	var second = ClassDB.instantiate("OnnxLoader")
	if first == null or second == null:
		_fail("OnnxLoader class is unavailable")
		return
	if not first.load_model(MODEL) or not second.load_model(MODEL):
		_fail("two live models could not be loaded")
		return
	var replacements := 0
	for run_index in RUNS:
		if run_index > 0 and run_index % 100 == 0:
			if not first.load_model(MODEL):
				_fail("model replacement failed: " + first.get_last_error())
				return
			replacements += 1
		if not _run_once(first, run_index) or not _run_once(second, RUNS - run_index):
			_fail("inference failed at run %d: %s / %s" % [
				run_index, first.get_last_error(), second.get_last_error()
			])
			return
	var first_diag: Dictionary = first.get_diagnostics()
	var second_diag: Dictionary = second.get_diagnostics()
	if int(second_diag.get("input_tensor_allocations", 0)) != 2:
		_fail("second loader did not retain two reusable input tensors")
		return
	if int(second_diag.get("input_tensor_reuses", 0)) != 2 * (RUNS - 1):
		_fail("second loader reuse count is wrong: %s" % second_diag)
		return
	first.unload_model()
	second.unload_model()
	first = null
	second = null
	print("GODOT_ONNX_LIFECYCLE_OK live_models=2 runs=%d replacements=%d final=%s" % [
		RUNS * 2, replacements, first_diag
	])
	get_tree().quit(0)
