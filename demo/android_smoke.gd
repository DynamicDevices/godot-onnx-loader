extends Node
## Exported Android smoke: exercises inference, tensor reuse, and real teardown.

const PACKED_MODEL := "res://models/ci_model.onnx"
const WRITABLE_MODEL := "user://ci_model.onnx"
const SESSION_COUNT := 8
const RUNS_PER_SESSION := 64


func _fail(message: String) -> void:
	push_error("ANDROID_ONNX_SMOKE_FAILED " + message)
	get_tree().quit(1)


func _copy_model_from_pack() -> bool:
	var source := FileAccess.open(PACKED_MODEL, FileAccess.READ)
	if source == null:
		_fail("cannot open packed model: %s" % PACKED_MODEL)
		return false
	var destination := FileAccess.open(WRITABLE_MODEL, FileAccess.WRITE)
	if destination == null:
		_fail("cannot create writable model: %s" % WRITABLE_MODEL)
		return false
	destination.store_buffer(source.get_buffer(source.get_length()))
	destination.close()
	source.close()
	return true


func _ready() -> void:
	if not _copy_model_from_pack():
		return
	var allocations := 0
	var reuses := 0
	var completed_runs := 0
	for session_index in SESSION_COUNT:
		var loader = ClassDB.instantiate("OnnxLoader")
		if loader == null:
			_fail("OnnxLoader class is unavailable")
			return
		if not loader.load_model(WRITABLE_MODEL):
			_fail("load session %d: %s" % [session_index, loader.get_last_error()])
			return
		var input := PackedFloat32Array()
		input.resize(loader.get_input_size())
		for run_index in RUNS_PER_SESSION:
			for i in input.size():
				input[i] = sin(float(i + run_index) * 0.017)
			var output: PackedFloat32Array = loader.predict(input)
			if output.size() != loader.get_output_size() or output.is_empty():
				_fail("inference session=%d run=%d: %s" % [
					session_index, run_index, loader.get_last_error()
				])
				return
			completed_runs += 1
		var diag: Dictionary = loader.get_diagnostics()
		allocations += int(diag.get("input_tensor_allocations", 0))
		reuses += int(diag.get("input_tensor_reuses", 0))
		loader.unload_model()
		loader = null
	if allocations != SESSION_COUNT or reuses != SESSION_COUNT * (RUNS_PER_SESSION - 1):
		_fail("unexpected tensor reuse allocations=%d reuses=%d" % [allocations, reuses])
		return
	print("ANDROID_ONNX_SMOKE_OK sessions=%d runs=%d allocations=%d reuses=%d" % [
		SESSION_COUNT, completed_runs, allocations, reuses
	])
	print("ANDROID_ONNX_TEARDOWN_OK")
	get_tree().quit(0)
