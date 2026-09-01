extends Node
## CSV → OnnxLoader.predict smoke (vizemes ci-smoke fixture).
## Run main scene in Godot 4.3 after building the addon .so.

func _softmax(logits: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(logits.size())
	if logits.is_empty():
		return out
	var m := logits[0]
	for i in range(1, logits.size()):
		if logits[i] > m:
			m = logits[i]
	var sum := 0.0
	for i in logits.size():
		out[i] = exp(logits[i] - m)
		sum += out[i]
	if sum <= 0.0:
		sum = 1.0
	for i in logits.size():
		out[i] /= sum
	return out


func _ready() -> void:
	var root := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	var json_path := root.path_join("fixtures/ci-smoke/model.json")
	var onnx_path := root.path_join("fixtures/ci-smoke/model.onnx")
	var csv_path := root.path_join("fixtures/ci-smoke/demo_inputs.csv")

	var m = ClassDB.instantiate("OnnxLoader")
	if m == null:
		push_error("OnnxLoader class missing — is onnx_loader.gdextension loaded?")
		get_tree().quit(1)
		return
	if not m.load_model(onnx_path):
		push_error("load_model failed: %s" % onnx_path)
		get_tree().quit(1)
		return
	print("ONNX_LOADER_DIAG ", m.get_diagnostics())
	var inputs: Array = m.get_input_descriptors()
	var outputs: Array = m.get_output_descriptors()
	if inputs.size() != 1 or outputs.size() < 1:
		push_error("unexpected fixture descriptors: %s / %s" % [inputs, outputs])
		get_tree().quit(1)
		return
	if m.run():
		push_error("run unexpectedly accepted an unbound required input")
		get_tree().quit(1)
		return
	var input_name: String = inputs[0]["name"]
	var input_shape: PackedInt64Array = inputs[0]["shape"]
	for i in input_shape.size():
		if input_shape[i] <= 0:
			input_shape[i] = 1
	var output_name: String = outputs[0]["name"]

	var nfeat: int = m.get_input_size()
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("open csv failed: %s" % csv_path)
		get_tree().quit(1)
		return
	var _header := file.get_csv_line()
	var hits := 0
	var n := 0
	print("%5s  %-8s  %-8s  hit" % ["probe", "expect", "argmax"])
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3 + nfeat:
			continue
		var probe := int(row[0])
		var expect_id := int(row[1])
		var expect_name := str(row[2])
		var ctx := PackedFloat32Array()
		ctx.resize(nfeat)
		for i in nfeat:
			ctx[i] = float(row[3 + i])
		var logits := PackedFloat32Array()
		if n == 0:
			if not m.set_input(input_name, ctx, input_shape):
				push_error("set_input failed: %s" % m.get_last_error())
				get_tree().quit(1)
				return
			if not m.run(PackedStringArray([output_name])):
				push_error("named run failed: %s" % m.get_last_error())
				get_tree().quit(1)
				return
			if m.get_run_generation() != 1 or not m.has_output(output_name):
				push_error("named output generation/cache contract failed")
				get_tree().quit(1)
				return
			logits = m.get_output(output_name)
			if logits.is_empty() or m.get_output_shape(output_name).is_empty():
				push_error("named output retrieval failed")
				get_tree().quit(1)
				return
			var bad_run_succeeded: bool = m.run(PackedStringArray(["not_a_model_output"]))
			if bad_run_succeeded or m.has_output(output_name) or m.get_run_generation() != 1:
				push_error("failed run exposed stale output or changed generation")
				get_tree().quit(1)
				return
			print("GODOT_ONNX_NAMED_API_OK generation=%d" % m.get_run_generation())
		else:
			logits = m.predict(ctx)
		if logits.is_empty():
			push_error("predict failed probe=%d" % probe)
			get_tree().quit(1)
			return
		var w := _softmax(logits)
		var argmax := 0
		for i in range(1, w.size()):
			if w[i] > w[argmax]:
				argmax = i
		var hit := argmax == expect_id
		hits += 1 if hit else 0
		n += 1
		print("%5d  %-8s  %8d  %s" % [probe, expect_name, argmax, "Y" if hit else "."])
	print("hit_rate=%d/%d" % [hits, n])
	print("GODOT_ONNX_CSV_SMOKE_OK rows=%d" % n)
	m.unload_model()
	m = null
	get_tree().quit(0 if n > 0 else 1)
