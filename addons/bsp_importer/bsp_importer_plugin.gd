@tool
extends EditorImportPlugin
class_name BSPImporterPlugin


func _get_importer_name():
	return "bsp"


func _get_visible_name():
	return "Quake BSP"


func _get_recognized_extensions():
	return ["bsp"]


func _get_priority():
	return 1.0


func _get_import_order():
	return 0


func _get_save_extension():
	return "scn"


func _get_resource_type():
	return "PackedScene"


enum Presets { DEFAULT }


func _get_preset_count():
	return Presets.size()


func _get_preset_name(preset):
	match preset:
		Presets.DEFAULT:
			return "Default"
		_:
			return "Unknown"


func _get_import_options(_path : String, preset_index : int):
	match preset_index:
		Presets.DEFAULT:
			return [{
				"name" : "inverse_scale_factor",
				"default_value" : 32.0
			},
			{
				"name" : "material_path_pattern",
				"default_value" : "res://materials/{texture_name}_material.tres"
			},
			{
				"name" : "texture_material_rename",
				"default_value" : { "texture_name1" : "res://material/texture_name1_material.tres" }
			},
			{
				"name" : "water_scene_template",
				"default_value" : "res://addons/bsp_importer/water_example_template.tscn"
			},
			{
				"name" : "slime_scene_template",
				"default_value" : "res://addons/bsp_importer/slime_example_template.tscn"
			},
			{
				"name" : "lava_scene_template",
				"default_value" : "res://addons/bsp_importer/lava_example_template.tscn"
			},
			{
				"name" : "entity_remap",
				"default_value" : { &"trigger_example" : "res://triggers/trigger_example.tres" }
			},
			## Can we have tooltips here?
			{
				"name" : "entity_offsets_quake_units",
				"default_value" : { &"example_offset_entity" : Vector3(16, 16, 0) }
			},
			{
				"name" : "import_lights",
				"default_value" : true
			},
			{
				"name" : "generate_occlusion_culling",
				"default_value" : true
			},
			{
				"name" : "culling_textures_exclude",
				"default_value" : [] as Array[StringName]
			},
			{
				"name" : "separate_mesh_on_grid",
				"default_value" : false
			},
			{
				"name" : "mesh_separation_grid_size",
				"default_value" : 256.0
			},
			{
				"name" : "post_import_script",
				"default_value" : ""
			}]
		_:
			return []


func _get_option_visibility(_option, _options, _unknown_dictionary):
	return true


func _import(source_file : String, save_path : String, options, r_platform_variants, r_gen_files):
	var bsp_reader := BSPReader.new()
	bsp_reader.material_path_pattern = options["material_path_pattern"]
	bsp_reader.water_template_path = options["water_scene_template"]
	bsp_reader.slime_template_path = options["slime_scene_template"]
	bsp_reader.lava_template_path = options["lava_scene_template"]
	bsp_reader.inverse_scale_fac = options["inverse_scale_factor"]
	bsp_reader.separate_mesh_on_grid = options["separate_mesh_on_grid"]
	bsp_reader.mesh_separation_grid_size = options["mesh_separation_grid_size"]
	bsp_reader.entity_remap = options.entity_remap
	bsp_reader.entity_offsets_quake_units = options.entity_offsets_quake_units
	bsp_reader.texture_material_rename = options.texture_material_rename
	bsp_reader.import_lights = options["import_lights"]
	bsp_reader.generate_occlusion_culling = options["generate_occlusion_culling"]
	bsp_reader.culling_textures_exclude = options.culling_textures_exclude
	bsp_reader.post_import_script_path = options["post_import_script"]

	var bsp_scene := bsp_reader.read_bsp(source_file)
	if (!bsp_scene):
		return bsp_scene.error

	var packed_scene := PackedScene.new()
	var err := packed_scene.pack(bsp_scene)
	if (err):
		print("Failed to pack scene: ", err)
		return err

	print("Saving to %s.%s" % [save_path, _get_save_extension()])
	return ResourceSaver.save(packed_scene, "%s.%s" % [save_path, _get_save_extension()])

