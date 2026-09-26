extends SceneTree

func _initialize() -> void:
	var loader = ClassDB.instantiate("OnnxLoader")
	if loader == null or loader.load_model("res://models/does-not-exist.onnx"):
		push_error("missing model unexpectedly loaded")
		quit(1)
		return
	var detail: String = loader.get_last_error()
	if not detail.contains("model not found"):
		push_error("load error was not preserved: %s" % detail)
		quit(1)
		return
	print("ONNX_LOAD_ERROR_PRESERVED_OK ", detail)
	quit(0)
