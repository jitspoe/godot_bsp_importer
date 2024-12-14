extends Node
class_name BSPReader

# =====================================================
# Constants and Enums
# =====================================================

const USE_BSPX_BRUSHES := true  # If -wrbrushes is used, use the extra brush data for collision.
const TEST_BOX_ONLY_COLLISION := false # For performance testing using only boxes.
const SINGLE_STATIC_BODY := true

# Quake CONTENTS constants
const CONTENTS_EMPTY := -1
const CONTENTS_SOLID := -2
const CONTENTS_WATER := -3
const CONTENTS_SLIME := -4
const CONTENTS_LAVA := -5

# Extended Quake CONTENTS (unused in logic, but listed for completeness):
# CONTENTS_SKY          = -6
# CONTENTS_ORIGIN       = -7
# CONTENTS_CLIP         = -8
# CONTENTS_CURRENT_0    = -9
# CONTENTS_CURRENT_90   = -10
# CONTENTS_CURRENT_180  = -11
# CONTENTS_CURRENT_270  = -12
# CONTENTS_CURRENT_UP   = -13
# CONTENTS_CURRENT_DOWN = -14
# CONTENTS_TRANSLUCENT  = -15

# Length for BSPX name
const BSPX_NAME_LENGTH := 24

# Structures size constants
const CLIPNODES_STRUCT_SIZE := (4 + 2 + 2) 
const NODES_STRUCT_SIZE_Q1BSP := (4 + 2 + 2 + 2 * 6 + 2 + 2)
const NODES_STRUCT_SIZE_Q1BSP2 := (4 + 4 + 4 + 4 * 6 + 4 + 4)

const LEAF_SIZE_Q1BSP := 4 + 4 + 2 * 6 + 2 + 2 + 1 + 1 + 1 + 1
const LEAF_SIZE_BSP2 := 4 + 4 + 4 * 6 + 4 + 4 + 1 + 1 + 1 + 1

const BSPX_NAME := "BSPX"

# Bit manipulation constants for signed/unsigned conversions
const MAX_15B := 1 << 15
const MAX_16B := 1 << 16
const MAX_31B = 1 << 31
const MAX_32B = 1 << 32

# Indices for lumps
enum {
	LUMP_ENT,
	LUMP_PLANE,
	LUMP_TEXTURE,
	LUMP_VERT,
	LUMP_VIS,
	LUMP_NODES,
	LUMP_TEXINFO,
	LUMP_FACES,
	LUMP_LIGHTMAP,
	LUMP_CLIPNODES,
	LUMP_LEAVES,
	LUMP_FACE_LIST,
	LUMP_EDGES,
	LUMP_LISTEDGES,
	LUMP_MODELS
}


# =====================================================
# Helper Classes
# =====================================================

class BSPEdge:
	var vertex_index_0 : int
	var vertex_index_1 : int

	func read_edge_16_bit(file : FileAccess) -> int:
		vertex_index_0 = file.get_16()
		vertex_index_1 = file.get_16()
		return 4

	func read_edge_32_bit(file : FileAccess) -> int:
		vertex_index_0 = file.get_32()
		vertex_index_1 = file.get_32()
		return 8

class BSPModelData:
	var bound_min : Vector3
	var bound_max : Vector3
	var origin : Vector3
	var node_id0 : int
	var node_id1 : int
	var node_id2 : int
	var node_id3 : int
	var num_leafs : int
	var face_index : int
	var face_count : int

class BSPModelDataQ2:
	var bound_min : Vector3
	var bound_max : Vector3
	var origin : Vector3
	var node_id0 : int

	static func get_data_size() -> int:
		return 2 * 3 * 4 + 3 * 4 + 1 * 4

	func read_model(file : FileAccess):
		bound_min = Vector3(file.get_float(), file.get_float(), file.get_float())
		bound_max = Vector3(file.get_float(), file.get_float(), file.get_float())
		origin = Vector3(file.get_float(), file.get_float(), file.get_float())
		node_id0 = file.get_32()

class MaterialInfo:
	var width : int
	var height : int
	var material : Material

class BSPTexture:
	var name : StringName
	var width : int
	var height : int
	var material : Material
	var is_warp := false
	var is_transparent := false

	static func get_data_size() -> int:
		return 40

	func read_texture(file : FileAccess, reader : BSPReader) -> int:
		var texture_header_file_offset := file.get_position()
		name = file.get_buffer(16).get_string_from_ascii()

		if name.begins_with("*"):
			name = name.substr(1)
			is_warp = true
			is_transparent = true

		if name.begins_with(reader.transparent_texture_prefix):
			name = name.substr(reader.transparent_texture_prefix.length())
			is_transparent = true

		width = file.get_32()
		height = file.get_32()
		var texture_data_offset := BSPReader.unsigned32_to_signed(file.get_32())
		if texture_data_offset > 0:
			texture_data_offset += texture_header_file_offset

		# Skip mip-level offsets
		file.get_32()
		file.get_32()
		file.get_32()

		name = name.to_lower()
		print("texture: ", name, " width: ", width, " height: ", height)

		if ![ "skip", "trigger", "waterskip", "slimeskip", "clip"].has(name):
			var material_info := reader.load_or_create_material(name, self)
			material = material_info.material
			width = material_info.width
			height = material_info.height

		return get_data_size()

class BSPTextureInfo:
	var vec_s : Vector3
	var offset_s : float
	var vec_t : Vector3
	var offset_t : float
	var texture_index : int
	var flags : int
	var value : int
	var texture_path : String

	static func get_data_size() -> int:
		return 40

	func read_texture_info(file : FileAccess) -> int:
		vec_s = BSPReader.read_vector_convert_unscaled(file)
		offset_s = file.get_float()
		vec_t = BSPReader.read_vector_convert_unscaled(file)
		offset_t = file.get_float()
		texture_index = file.get_32()
		flags = file.get_32()
		return get_data_size()

class BSPFace:
	var plane_id : int
	var plane_side : int
	var edge_list_id : int
	var num_edges : int
	var texinfo_id : int
	var light_type : int
	var light_base : int
	var light_model_0 : int
	var light_model_1 : int
	var lightmap : int
	var verts : PackedVector3Array = []

	static func get_data_size_q1bsp() -> int:
		return 20

	static func get_data_size_bsp2() -> int:
		return 20 + 2 * 4

	func read_face_q1bsp(file : FileAccess) -> int:
		plane_id = file.get_16()
		plane_side = file.get_16()
		edge_list_id = file.get_32()
		num_edges = file.get_16()
		texinfo_id = file.get_16()
		light_type = file.get_8()
		light_base = file.get_8()
		light_model_0 = file.get_8()
		light_model_1 = file.get_8()
		lightmap = file.get_32()
		return get_data_size_q1bsp()

	func read_face_bsp2(file : FileAccess) -> int:
		plane_id = file.get_32()
		plane_side = file.get_32()
		edge_list_id = file.get_32()
		num_edges = file.get_32()
		texinfo_id = file.get_32()
		light_type = file.get_8()
		light_base = file.get_8()
		light_model_0 = file.get_8()
		light_model_1 = file.get_8()
		lightmap = file.get_32()
		return get_data_size_bsp2()


class BSPXBrush:
	var mins : Vector3
	var maxs : Vector3
	var contents : int
	var planes : Array[Plane] = []


# =====================================================
# Static Helper Functions
# =====================================================

static var default_palette : PackedByteArray = []

static func unsigned16_to_signed(unsigned : int) -> int:
	return (unsigned + MAX_15B) % MAX_16B - MAX_15B

static func unsigned32_to_signed(unsigned : int) -> int:
	return (unsigned + MAX_31B) % MAX_32B - MAX_31B

static func convert_vector_from_quake_unscaled(quake_vector : Vector3) -> Vector3:
	# Quake: X forward, Z up. Godot: Z forward, Y up. So we rearrange axes.
	return Vector3(-quake_vector.y, quake_vector.z, -quake_vector.x)

static func convert_vector_from_quake_scaled(quake_vector : Vector3, scale: float) -> Vector3:
	return convert_vector_from_quake_unscaled(quake_vector) * scale

static func read_vector_convert_unscaled(file : FileAccess) -> Vector3:
	return convert_vector_from_quake_unscaled(Vector3(file.get_float(), file.get_float(), file.get_float()))

static func get_lumps_end(current_end : int, offset : int, length : int) -> int:
	return max(current_end, offset + length)


# =====================================================
# BSPReader Class
# =====================================================

var error := ERR_UNCONFIGURED
var save_separate_materials := false
var material_path_pattern : String
var texture_material_rename : Dictionary
var texture_path_pattern : String
var texture_emission_path_pattern : String
var texture_path_remap : Dictionary
var transparent_texture_prefix : String
var texture_palette_path : String
var entity_path_pattern : String
var water_template : PackedScene
var slime_template : PackedScene
var lava_template : PackedScene
var entity_remap : Dictionary
var entity_offsets_quake_units : Dictionary
var array_of_planes_array := []
var array_of_planes : PackedInt32Array = []
var water_planes_array := []
var slime_planes_array := []
var lava_planes_array := []
var file : FileAccess
var leaves_offset : int
var nodes_offset : int
var root_node : Node3D
var plane_normals : PackedVector3Array
var plane_distances : PackedFloat32Array
var model_scenes : Dictionary = {}
var is_bsp2 := false
var _unit_scale : float = 1.0
var import_lights := true
var light_brightness_scale := 16.0
var generate_occlusion_culling := true
var generate_shadow_mesh := false
var use_triangle_collision := false
var culling_textures_exclude : Array[StringName]
var generate_lightmap_uv2 := true
var post_import_script_path : String
var separate_mesh_on_grid := false
var generate_texture_materials := false
var overwrite_existing_materials := false
var overwrite_existing_textures := false
var mesh_separation_grid_size := 256.0
var bspx_model_to_brush_map := {}
var fullbright_range : PackedInt32Array = [224, 255]
var inverse_scale_fac : float = 32.0:
	set(v):
		inverse_scale_fac = v
		_unit_scale = 1.0 / v

var post_import_nodes : Array[Node] = []

# =====================================================
# Public Functions
# =====================================================

func clear_data():
	error = ERR_UNCONFIGURED
	array_of_planes_array = []
	array_of_planes = []
	water_planes_array = []
	slime_planes_array = []
	lava_planes_array = []
	if file:
		file.close()
		file = null
	root_node = null
	plane_normals = []
	plane_distances = []
	model_scenes = {}

func read_bsp(source_file : String) -> Node:
	clear_data()
	print("Attempting to import %s" % source_file)
	print("Material path pattern: ", material_path_pattern)
	file = FileAccess.open(source_file, FileAccess.READ)
	if !file:
		error = FileAccess.get_open_error()
		print("Failed to open %s: %d" % [source_file, error])
		return null

	root_node = Node3D.new()
	root_node.name = source_file.get_file().get_basename()
	
	is_bsp2 = false
	
	var options = {
		"is_q2": false,
		"is_q3": false,
		"has_textures": true,
		"has_clipnodes": true,
		"has_brush_table": false,
		"bsp_version": file.get_32(),
		"index_bits_32": false,
	}
	print("BSP version: %d\n" % options.bsp_version)

	# Check for different BSP formats
	if options.bsp_version == 1347633737: # "IBSP" quake2
		options.is_q2 = true
		options.has_textures = false
		options.has_clipnodes = false
		options.has_brush_table = true
		options.bsp_version = file.get_32()
		
		if (options.bsp_version == 46 or options.bsp_version == 47):
			# Quake 3 BSP format
			options.is_q3 = true
			print("Detected Quake 3 BSP (IBSP v%d)." % options.bsp_version)
			return convertBSP3toScene(source_file)
		else:
			print("Quake 2 BSP Format Detected.")
			file.close()
			file = null
			return convertBSP2toScene(source_file)

	if options.bsp_version == 1112756274: # "2PSB"
		print("2PSB format not supported.")
		file.close()
		file = null
		return null

	if options.bsp_version == 844124994: # "BSP2"
		print("BSP2 extended Quake format.")
		is_bsp2 = true
		options.index_bits_32 = true
		
	return convertBSPtoScene(options)

func convertBSPtoScene(options: Dictionary):
	# Read lumps
	var entity_offset := file.get_32()
	var entity_size := file.get_32()
	var bsp_end := get_lumps_end(0, entity_offset, entity_size)

	var planes_offset := file.get_32()
	var planes_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, planes_offset, planes_size)

	var textures_offset := (file.get_32() if options.has_textures else 0)
	var textures_size := (file.get_32() if options.has_textures else 0)
	bsp_end = get_lumps_end(bsp_end, textures_offset, textures_size)

	var verts_offset := file.get_32()
	var verts_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, verts_offset, verts_size)

	var vis_offset := file.get_32()
	var vis_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, vis_offset, vis_size)

	nodes_offset = file.get_32()
	var nodes_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, nodes_offset, nodes_size)

	var texinfo_offset := file.get_32()
	var texinfo_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, texinfo_offset, texinfo_size)

	var faces_offset := file.get_32()
	var faces_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, faces_offset, faces_size)

	var lightmaps_offset := file.get_32()
	var lightmaps_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, lightmaps_offset, lightmaps_size)

	var clipnodes_offset := (file.get_32() if options.has_clipnodes else 0)
	var clipnodes_size := (file.get_32() if options.has_clipnodes else 0)
	bsp_end = get_lumps_end(bsp_end, clipnodes_offset, clipnodes_size)

	leaves_offset = file.get_32()
	var leaves_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, leaves_offset, leaves_size)

	var listfaces_size := file.get_32()
	var listfaces_offset := file.get_32()
	bsp_end = get_lumps_end(bsp_end, listfaces_offset, listfaces_size)

	var leaf_brush_table_offset := (file.get_32() if options.has_brush_table else 0)
	var leaf_brush_table_size := (file.get_32() if options.has_brush_table else 0)
	bsp_end = get_lumps_end(bsp_end, leaf_brush_table_offset, leaf_brush_table_size)

	var edges_offset := file.get_32()
	var edges_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, edges_offset, edges_size)

	var listedges_offset := file.get_32()
	var listedges_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, listedges_offset, listedges_size)

	var models_offset := file.get_32()
	var models_size := file.get_32()
	bsp_end = get_lumps_end(bsp_end, models_offset, models_size)

	# Q2-specific lumps (if any)
	var brushes_offset := (file.get_32() if options.has_brush_table else 0)
	var brushes_size := (file.get_32() if options.has_brush_table else 0)
	bsp_end = get_lumps_end(bsp_end, brushes_offset, brushes_size)

	var brush_sides_offset := (file.get_32() if options.has_brush_table else 0)
	var brush_sides_size := (file.get_32() if options.has_brush_table else 0)
	bsp_end = get_lumps_end(bsp_end, brush_sides_offset, brush_sides_size)

	# Check for BSPX section
	var has_bspx := false
	var bspx_offset := bsp_end
	bspx_offset = ((bspx_offset + 3) / 4) * 4
	file.seek(bspx_offset)
	var bspx_check := file.get_32()
	var use_bspx_brushes := false
	if bspx_check == 1481659202: # 'BSPX'
		has_bspx = true
		var has_bspx_brushes := false
		var bspx_brushes_offset := 0
		var bspx_brushes_length := 0
		var num_bspx_entries := file.get_32()
		for i in num_bspx_entries:
			var entry_name := file.get_buffer(BSPX_NAME_LENGTH).get_string_from_ascii()
			print("BSPX entry: ", entry_name)
			var off := file.get_32()
			var length := file.get_32()
			if entry_name == "BRUSHLIST":
				has_bspx_brushes = true
				bspx_brushes_offset = off
				bspx_brushes_length = length

		if has_bspx_brushes and USE_BSPX_BRUSHES:
			use_bspx_brushes = true
			read_bspx_brushes(bspx_brushes_offset, bspx_brushes_length)
	else:
		print("Does not have BSPX.")

	# Read vertices
	file.seek(verts_offset)
	var vertex_count := verts_size / (4 * 3)
	var verts := PackedVector3Array()
	verts.resize(vertex_count)
	for i in vertex_count:
		verts[i] = convert_vector_from_quake_scaled(Vector3(file.get_float(), file.get_float(), file.get_float()), _unit_scale)

	# Read entity string
	file.seek(entity_offset)
	var entity_string : String = file.get_buffer(entity_size).get_string_from_ascii()
	var entity_dict_array := parse_entity_string(entity_string)
	convert_entity_dict_to_scene(entity_dict_array)

	# Read edges
	file.seek(edges_offset)
	var edges = []
	var edges_data_left := edges_size
	while edges_data_left > 0:
		var edge := BSPEdge.new()
		if options.index_bits_32:
			edges_data_left -= edge.read_edge_32_bit(file)
		else:
			edges_data_left -= edge.read_edge_16_bit(file)
		edges.append(edge)

	# Read listedges
	var edge_list : PackedInt32Array
	var num_edge_list := listedges_size / 4
	edge_list = PackedInt32Array()
	edge_list.resize(num_edge_list)
	file.seek(listedges_offset)
	for i in num_edge_list:
		edge_list[i] = file.get_32()

	# Read planes
	var num_planes := planes_size / (4 * 5)
	plane_normals = PackedVector3Array()
	plane_distances = PackedFloat32Array()
	plane_normals.resize(num_planes)
	plane_distances.resize(num_planes)
	file.seek(planes_offset)
	for i in num_planes:
		var quake_plane_normal := Vector3(file.get_float(), file.get_float(), file.get_float())
		plane_normals[i] = convert_vector_from_quake_unscaled(quake_plane_normal)
		plane_distances[i] = file.get_float() * _unit_scale
		file.get_32() # plane type (unused)

	# Textures
	var textures = []
	if options.has_textures:
		file.seek(textures_offset)
		var num_textures = file.get_32()
		var texture_offset_offsets = PackedInt32Array()
		texture_offset_offsets.resize(num_textures)
		textures.resize(num_textures)

		for i in num_textures:
			texture_offset_offsets[i] = file.get_32()

		for i in num_textures:
			var texture_offset = texture_offset_offsets[i]
			if texture_offset < 0:
				var bad_tex = BSPTexture.new()
				bad_tex.width = 64
				bad_tex.height = 64
				bad_tex.name = "_bad_texture_"
				textures[i] = bad_tex
			else:
				file.seek(textures_offset + texture_offset)
				var tex = BSPTexture.new()
				tex.read_texture(file, self)
				textures[i] = tex

	# Texinfo
	file.seek(texinfo_offset)
	var num_texinfo := texinfo_size / BSPTextureInfo.get_data_size()
	var textureinfos = []
	textureinfos.resize(num_texinfo)
	for i in num_texinfo:
		var tinfo = BSPTextureInfo.new()
		tinfo.read_texture_info(file)
		textureinfos[i] = tinfo

	# Models
	var model_data_size := (2 * 3 * 4 + 3 * 4 + 7 * 4) if !options.is_q2 else BSPModelDataQ2.get_data_size()
	var num_models := models_size / model_data_size
	var model_data = []
	model_data.resize(num_models)
	for i in num_models:
		file.seek(models_offset + model_data_size * i)
		if options.is_q2:
			var q2_model = BSPModelDataQ2.new()
			q2_model.read_model(file)
			model_data[i] = q2_model
		else:
			var q1_model = BSPModelData.new()
			read_model_data_q1_bsp(q1_model)
			model_data[i] = q1_model

	# Faces
	file.seek(faces_offset)
	var bsp_face = BSPFace.new()

	# Construct scene from models
	for model_index in num_models:
		build_model_geometry(model_index, model_data, faces_offset, faces_size, textures, textureinfos, verts, edges, edge_list, options.index_bits_32)

	# Run post-import script
	run_post_import_script()

	file.close()
	file = null
	print("BSP read complete.")
	return root_node

# =====================================================
# Private Helper Functions
# =====================================================

func read_bspx_brushes(bspx_brushes_offset : int, bspx_brushes_length : int):
	file.seek(bspx_brushes_offset)
	var bytes_read := 0
	while file.get_position() < file.get_length():
		if bytes_read >= bspx_brushes_length:
			break
		var version := file.get_32()
		bytes_read += 4
		if version != 1:
			print("Only BSPX brush version 1 supported. Version: ", version)
			break
		var model_num := file.get_32()
		bytes_read += 4
		var brush_array : Array[BSPXBrush] = bspx_model_to_brush_map.get(model_num, [])

		var num_brushes := file.get_32()
		bytes_read += 4
		var num_planes_total := file.get_32()
		bytes_read += 4

		for brush_index in num_brushes:
			var bspx_brush := BSPXBrush.new()
			var mins := read_vector_convert_scaled()
			bytes_read += 12
			var maxs := read_vector_convert_scaled()
			bytes_read += 12

			bspx_brush.mins = Vector3(min(mins.x, maxs.x), min(mins.y, maxs.y), min(mins.z, maxs.z))
			bspx_brush.maxs = Vector3(max(mins.x, maxs.x), max(mins.y, maxs.y), max(mins.z, maxs.z))
			bspx_brush.contents = unsigned16_to_signed(file.get_16())
			bytes_read += 2
			var num_bspx_planes := file.get_16()
			bytes_read += 2

			for plane_index in num_bspx_planes:
				var normal := read_vector_convert_unscaled(file)
				bytes_read += 12
				var dist := file.get_float() * _unit_scale
				bytes_read += 4
				var plane := Plane(normal, dist)
				bspx_brush.planes.append(plane)

			brush_array.append(bspx_brush)
		bspx_model_to_brush_map[model_num] = brush_array

func run_post_import_script():
	if post_import_script_path:
		print("Loading post import script: ", post_import_script_path)
		var script = load(post_import_script_path)
		if script and script is Script:
			var post_import_node := Node.new()
			post_import_node.set_script(script)
			if post_import_node.has_method("post_import"):
				if post_import_node.get_script().is_tool():
					post_import_node.post_import(root_node)
				else:
					printerr("Post import script must have @tool set.")
			else:
				printerr("Post import script does not have post_import() function.")
		else:
			printerr("Invalid script path: ", post_import_script_path)

	for node in post_import_nodes:
		node.post_import(root_node)

func parse_entity_string(entity_string : String) -> Array:
	var ent_dict_array := []
	var ent_dict := {}
	var in_key_string = false
	var in_value_string = false
	var key = ""
	var value = ""
	var parsed_key = false

	for char in entity_string:
		if in_key_string:
			if char == '"':
				in_key_string = false
				parsed_key = true
			else:
				key += char
		elif in_value_string:
			if char == '"':
				in_value_string = false
				ent_dict[key] = value
				key = ""
				value = ""
				parsed_key = false
			else:
				value += char
		else:
			if char == '"':
				if parsed_key:
					in_value_string = true
				else:
					in_key_string = true
			elif char == '{':
				ent_dict = {}
				parsed_key = false
			elif char == '}':
				ent_dict_array.push_back(ent_dict)

	return ent_dict_array

func convert_entity_dict_to_scene(ent_dict_array : Array):
	post_import_nodes = []
	for ent_dict in ent_dict_array:
		if ent_dict.has("classname"):
			var classname : StringName = ent_dict["classname"].to_lower()
			var scene_path = ""
			if entity_remap.has(classname):
				scene_path = entity_remap[classname]
			else:
				if classname != "worldspawn":
					scene_path = entity_path_pattern.replace("{classname}", classname)

			if !scene_path.is_empty() and ResourceLoader.exists(scene_path):
				var scene_resource = load(scene_path)
				if !scene_resource:
					print("Failed to load ", scene_path)
				else:
					var scene_node : Node = scene_resource.instantiate()
					if !scene_node:
						print("Failed to instantiate scene: ", scene_path)
					else:
						if scene_node.has_method("post_import"):
							post_import_nodes.append(scene_node)

						add_generic_entity(scene_node, ent_dict)

						if scene_node.has_method("set_entity_dictionary"):
							if !scene_node.get_script().is_tool():
								printerr(scene_node.name + " 'set_entity_dictionary()' must have @tool set.")
							else:
								scene_node.set_entity_dictionary(ent_dict)

						apply_entity_values(scene_node, ent_dict)
			else:
				if classname == "light":
					if import_lights:
						add_light_entity(ent_dict)
				else:
					if classname != "worldspawn":
						if !scene_path.is_empty():
							printerr("Could not open ", scene_path, " for classname: ", classname)
						else:
							printerr("No entity remap found for ", classname)
	return

func apply_entity_values(scene_node : Node, ent_dict : Dictionary):
	for key in ent_dict.keys():
		var string_value : String = ent_dict[key]
		var value = string_value

		if key == "spawnflags":
			value = value.to_int()

		if scene_node.has_method("set_import_value"):
			if !scene_node.get_script().is_tool():
				printerr(scene_node.name + " has 'set_import_value()' but must have @tool set.")
			else:
				if scene_node.set_import_value(key, string_value):
					continue

		var dest_value = scene_node.get(key)
		if dest_value != null:
			var dest_type := typeof(dest_value)
			match dest_type:
				TYPE_BOOL: value = string_value.to_int() != 0
				TYPE_INT: value = string_value.to_int()
				TYPE_FLOAT: value = string_value.to_float()
				TYPE_STRING: value = string_value
				TYPE_STRING_NAME: value = string_value
				TYPE_VECTOR3: value = string_to_vector3(string_value)
				TYPE_COLOR: value = string_to_color(string_value)
				_:
					value = string_value
		scene_node.set(key, value)

func add_generic_entity(scene_node : Node, ent_dict : Dictionary):
	var origin := Vector3.ZERO
	if ent_dict.has("origin"):
		origin = string_to_origin(ent_dict["origin"], _unit_scale)

	var offset : Vector3 = convert_vector_from_quake_scaled(entity_offsets_quake_units.get(ent_dict["classname"], Vector3.ZERO), _unit_scale)
	origin += offset

	var mangle_string := ent_dict.get("mangle", "")
	var angle_string := ent_dict.get("angle", "")
	var angles_string := ent_dict.get("angles", "")

	var basis := Basis()
	if angle_string.length() > 0:
		basis = angle_string_to_basis(angle_string)
	if mangle_string.length() > 0:
		basis = mangle_string_to_basis(mangle_string)
	if angles_string.length() > 0:
		basis = angles_string_to_basis(angles_string)

	var transform := Transform3D(basis, origin)
	root_node.add_child(scene_node, true)
	scene_node.transform = transform
	scene_node.owner = root_node

	if ent_dict.has("model"):
		var model_value : String = ent_dict["model"]
		if model_value[0] == '*':
			model_scenes[model_value.substr(1).to_int()] = scene_node

func add_light_entity(ent_dict : Dictionary):
	var light_node := OmniLight3D.new()
	var light_value := 300.0
	var light_color := Color(1.0, 1.0, 1.0, 1.0)
	if ent_dict.has("light"):
		light_value = ent_dict["light"].to_float()

	if ent_dict.has("_color"):
		light_color = string_to_color(ent_dict["_color"])
	if ent_dict.has("color"):
		light_color = string_to_color(ent_dict["color"])

	light_node.omni_range = light_value * _unit_scale
	light_node.light_energy = light_value * light_brightness_scale / 255.0
	light_node.light_color = light_color
	light_node.shadow_enabled = true
	add_generic_entity(light_node, ent_dict)

func string_to_color(color_string : String) -> Color:
	var color = Color(1.0,1.0,1.0,1.0)
	var floats = color_string.split_floats(" ")
	var scale = 1.0
	for f in floats:
		if f > 1.0:
			scale = 1.0 / 255.0
			break
	for i in min(3, floats.size()):
		color[i] = floats[i] * scale
	return color

static func string_to_origin(origin_string : String, scale: float) -> Vector3:
	var vec = string_to_vector3(origin_string)
	return convert_vector_from_quake_scaled(vec, scale)

static func string_to_vector3(vec_string : String) -> Vector3:
	var vec = Vector3.ZERO
	var split = vec_string.split(" ")
	for i in range(min(3, split.size())):
		vec[i] = split[i].to_float()
	return vec

static func mangle_string_to_basis(mangle_string : String) -> Basis:
	return angles_string_to_basis_pyr(mangle_string, true)

static func angle_string_to_basis(angle_string : String) -> Basis:
	if angle_string == "-1":
		return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	if angle_string == "-2":
		return Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	var angles = Vector3.ZERO
	angles[1] = deg_to_rad(angle_string.to_float())
	return Basis.from_euler(angles)

static func angles_string_to_basis(angles_string : String) -> Basis:
	return angles_string_to_basis_pyr(angles_string, true)

static func angles_string_to_basis_pyr(angles_string : String, pitch_up_negative : bool) -> Basis:
	var angles = string_to_angles_pyr(angles_string, pitch_up_negative)
	return Basis.from_euler(angles)

static func string_to_angles_pyr(angles_string : String, pitch_up_negative : bool) -> Vector3:
	var split = angles_string.split(" ")
	var angles = Vector3.ZERO
	for i in range(min(3, split.size())):
		angles[i] = deg_to_rad(split[i].to_float())
	if pitch_up_negative:
		angles[0] = -angles[0]
	return angles

func build_model_geometry(model_index, model_data, faces_offset, faces_size, textures, textureinfos, verts, edges, edge_list, index_bits_32):
	var parent_node : Node3D = root_node
	var parent_inv_transform = Transform3D()
	var is_worldspawn = (model_index == 0)
	var needs_import = false
	if is_worldspawn:
		needs_import = true
		if SINGLE_STATIC_BODY:
			var static_body = StaticBody3D.new()
			static_body.name = "StaticBody"
			root_node.add_child(static_body, true)
			static_body.owner = root_node
			parent_node = static_body

	if model_scenes.has(model_index):
		needs_import = true
		parent_node = model_scenes[model_index]
		parent_inv_transform = Transform3D(parent_node.transform.basis.inverse(), Vector3.ZERO)

	if !needs_import:
		return

	var bsp_model = model_data[model_index]
	var face_size := (BSPFace.get_data_size_q1bsp() if !is_bsp2 else BSPFace.get_data_size_bsp2())
	file.seek(faces_offset + bsp_model.face_index * face_size)
	var num_faces = bsp_model.face_count

	var mesh_grid = {}
	water_planes_array = []
	slime_planes_array = []
	lava_planes_array = []

	# Build geometry for each face
	for face_index in num_faces:
		var bsp_face = BSPFace.new()
		if is_bsp2:
			bsp_face.read_face_bsp2(file)
		else:
			bsp_face.read_face_q1bsp(file)

		if bsp_face.texinfo_id >= textureinfos.size():
			printerr("Bad texinfo_id: ", bsp_face.texinfo_id)
			continue
		if bsp_face.num_edges < 3:
			printerr("Face with fewer than 3 edges.")
			continue

		var assembled_vertices = assemble_face_vertices(bsp_face, verts, edges, edge_list, textureinfos, textures)
		var face_verts = assembled_vertices[0]
		var face_normals = assembled_vertices[1]
		var face_uvs = assembled_vertices[2]
		if face_verts.size() < 3:
			continue

		var texture = textures[ textureinfos[bsp_face.texinfo_id].texture_index ]
		var surf_tool = get_surface_tool_for_face(mesh_grid, separate_mesh_on_grid, face_verts, texture, parent_inv_transform)

		surf_tool.add_triangle_fan(face_verts, face_uvs, [], [], face_normals)

		# Transparent faces committed immediately as separate meshes
		if texture.is_transparent:
			var mesh_instance = MeshInstance3D.new()
			surf_tool.generate_tangents()
			var array_mesh = surf_tool.commit()
			mesh_instance.mesh = array_mesh
			mesh_instance.name = "TransparentMesh"
			parent_node.add_child(mesh_instance, true)
			mesh_instance.transform = parent_inv_transform
			mesh_instance.owner = root_node

	# Commit surfaces from mesh grid
	commit_mesh_grid(mesh_grid, parent_node, parent_inv_transform, is_worldspawn)

	# Collision
	if use_triangle_collision:
		create_triangle_collision(mesh_grid, parent_node, parent_inv_transform)
	else:
		if bspx_model_to_brush_map.has(model_index) and USE_BSPX_BRUSHES:
			var bspx_brushes = bspx_model_to_brush_map[model_index]
			create_collision_from_brushes(parent_node, bspx_brushes, parent_inv_transform)
		else:
			build_collision_from_nodes(model_index, model_data, parent_node, parent_inv_transform)

func assemble_face_vertices(bsp_face, verts, edges, edge_list, textureinfos, textures) -> Array:
	var face_verts = PackedVector3Array()
	face_verts.resize(bsp_face.num_edges)

	var face_normals = PackedVector3Array()
	face_normals.resize(bsp_face.num_edges)

	var face_uvs = PackedVector2Array()
	face_uvs.resize(bsp_face.num_edges)

	var face_normal = Vector3.UP
	if bsp_face.plane_id < plane_normals.size():
		face_normal = plane_normals[bsp_face.plane_id]
	else:
		print("Plane id out of bounds: ", bsp_face.plane_id)
	if bsp_face.plane_side > 0:
		face_normal = -face_normal

	var tex_info = textureinfos[bsp_face.texinfo_id]
	var texture = textures[tex_info.texture_index]

	var vs = tex_info.vec_s
	var vt = tex_info.vec_t
	var s = tex_info.offset_s
	var t = tex_info.offset_t
	var tex_width = texture.width
	var tex_height = texture.height

	var tex_scale_x = 1.0 / (_unit_scale * tex_width)
	var tex_scale_y = 1.0 / (_unit_scale * tex_height)

	var face_position = Vector3.ZERO
	var edge_list_index_start = bsp_face.edge_list_id
	for i in range(bsp_face.num_edges):
		var edge_list_index = edge_list_index_start + i
		var edge_index = edge_list[edge_list_index]
		var reverse_order = (edge_index < 0)
		if reverse_order:
			edge_index = -edge_index

		var vert_index_0 = (edges[edge_index].vertex_index_1 if reverse_order else edges[edge_index].vertex_index_0)
		var vert = verts[vert_index_0]
		face_verts[i] = vert
		face_normals[i] = face_normal
		face_uvs[i].x = vert.dot(vs)*tex_scale_x + s/tex_width
		face_uvs[i].y = vert.dot(vt)*tex_scale_y + t/tex_height
		face_position += vert

	return [face_verts, face_normals, face_uvs]

func get_surface_tool_for_face(mesh_grid, separate_mesh_on_grid, face_verts, texture, parent_inv_transform):
	var surf_tool : SurfaceTool
	if texture.is_transparent:
		surf_tool = SurfaceTool.new()
		surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surf_tool.set_material(texture.material)
	else:
		var face_position = Vector3.ZERO
		for v in face_verts:
			face_position += v
		face_position /= face_verts.size()

		var grid_index = (Vector3i(face_position / mesh_separation_grid_size) if separate_mesh_on_grid else 0)
		var surface_tools = mesh_grid.get(grid_index, {})
		if surface_tools.has(texture.name):
			surf_tool = surface_tools[texture.name]
		else:
			surf_tool = SurfaceTool.new()
			surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			surf_tool.set_material(texture.material)
			surface_tools[texture.name] = surf_tool
		mesh_grid[grid_index] = surface_tools

	return surf_tool

func commit_mesh_grid(mesh_grid, parent_node : Node3D, parent_inv_transform : Transform3D, is_worldspawn : bool):
	for grid_index in mesh_grid:
		var surface_tools = mesh_grid[grid_index]
		var mesh_instance = MeshInstance3D.new()
		var array_mesh : ArrayMesh = null
		var has_nocull_materials = false

		for texture_name in surface_tools:
			var st : SurfaceTool = surface_tools[texture_name]
			st.generate_tangents()
			if culling_textures_exclude.has(texture_name):
				has_nocull_materials = true
			else:
				array_mesh = st.commit(array_mesh)

		if array_mesh or has_nocull_materials:
			mesh_instance.name = "Mesh"
			parent_node.add_child(mesh_instance, true)
			mesh_instance.transform = parent_inv_transform
			mesh_instance.owner = root_node

			if generate_occlusion_culling and array_mesh and is_worldspawn:
				var arraymesh_arrays = arraymesh_to_arrays(array_mesh)
				var vertices2 = arraymesh_arrays[0]
				var indices2 = arraymesh_arrays[1]
				var occluder = ArrayOccluder3D.new()
				occluder.set_arrays(vertices2, indices2)
				var occluder_instance = OccluderInstance3D.new()
				occluder_instance.occluder = occluder
				occluder_instance.name = "Occluder"
				mesh_instance.add_child(occluder_instance, true)
				occluder_instance.owner = root_node

			var shadow_mesh : ArrayMesh = null
			if generate_shadow_mesh:
				var arraymesh_arrays = arraymesh_to_arrays(array_mesh)
				var vertices2 = arraymesh_arrays[0]
				var indices2 = arraymesh_arrays[1]
				if indices2.size() >= 3:
					shadow_mesh = ArrayMesh.new()
					var mesh_arrays = []
					mesh_arrays.resize(ArrayMesh.ARRAY_MAX)
					mesh_arrays[ArrayMesh.ARRAY_VERTEX] = vertices2
					mesh_arrays[ArrayMesh.ARRAY_INDEX] = indices2
					shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
				array_mesh.shadow_mesh = shadow_mesh

			if has_nocull_materials:
				for texture_name in surface_tools:
					if culling_textures_exclude.has(texture_name):
						var st : SurfaceTool = surface_tools[texture_name]
						array_mesh = st.commit(array_mesh)

			mesh_instance.mesh = array_mesh

			if generate_lightmap_uv2:
				mesh_instance.mesh.lightmap_unwrap(mesh_instance.global_transform, _unit_scale * 4.0)

func arraymesh_to_arrays(array_mesh : ArrayMesh) -> Array:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	for i in array_mesh.get_surface_count():
		var offset = vertices.size()
		var arrays = array_mesh.surface_get_arrays(i)
		vertices.append_array(arrays[ArrayMesh.ARRAY_VERTEX])
		if arrays[ArrayMesh.ARRAY_INDEX] == null:
			indices.append_array(range(offset, offset + arrays[ArrayMesh.ARRAY_VERTEX].size()))
		else:
			for index in arrays[ArrayMesh.ARRAY_INDEX]:
				indices.append(index + offset)
	return [vertices, indices]

func create_triangle_collision(mesh_grid, parent_node : Node3D, parent_inv_transform : Transform3D):
	for grid_index in mesh_grid:
		var surface_tools = mesh_grid[grid_index]
		for texture_name in surface_tools:
			var st : SurfaceTool = surface_tools[texture_name]
			var array_mesh = st.commit()
			var collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape"
			collision_shape.shape = array_mesh.create_trimesh_shape()
			parent_node.add_child(collision_shape, true)
			collision_shape.transform = parent_inv_transform
			collision_shape.owner = root_node

func create_collision_from_brushes(parent : Node3D, brushes : Array[BSPXBrush], parent_inv_transform : Transform3D):
	var collision_index := 0
	var water_body : Node3D
	var slime_body : Node3D
	var lava_body : Node3D

	for brush in brushes:
		collision_index += 1
		var aabb = AABB(brush.mins, Vector3.ZERO).expand(brush.maxs)
		var center = aabb.get_center()

		var body_to_add_to : Node3D = parent
		match brush.contents:
			CONTENTS_SOLID:
				if !SINGLE_STATIC_BODY:
					var static_body_child := StaticBody3D.new()
					static_body_child.name = "StaticBody%d" % collision_index
					parent.add_child(static_body_child, true)
					static_body_child.owner = root_node
					body_to_add_to = static_body_child
			CONTENTS_WATER:
				if !water_body and water_template:
					water_body = water_template.instantiate()
					parent.add_child(water_body)
					water_body.owner = root_node
				body_to_add_to = water_body
			CONTENTS_SLIME:
				if !slime_body and slime_template:
					slime_body = slime_template.instantiate()
					parent.add_child(slime_body)
					slime_body.owner = root_node
				body_to_add_to = slime_body
			CONTENTS_LAVA:
				if !lava_body and lava_template:
					lava_body = lava_template.instantiate()
					parent.add_child(lava_body)
					lava_body.owner = root_node
				body_to_add_to = lava_body
			_:
				print("Unknown brush contents: ", brush.contents)

		if brush.planes.size() == 0:
			# Just a box
			var collision_shape := CollisionShape3D.new()
			collision_shape.name = "CollisionBox%d" % collision_index
			var box := BoxShape3D.new()
			box.size = aabb.size
			collision_shape.position = center
			collision_shape.shape = box
			body_to_add_to.add_child(collision_shape)
			collision_shape.owner = root_node
			collision_shape.transform = parent_inv_transform * collision_shape.transform
		else:
			# Build from planes
			var planes = brush.planes.duplicate()
			planes.push_back(Plane(Vector3.RIGHT, brush.maxs.x))
			planes.push_back(Plane(Vector3.UP, brush.maxs.y))
			planes.push_back(Plane(Vector3.BACK, brush.maxs.z))
			planes.push_back(Plane(Vector3.LEFT, -brush.mins.x))
			planes.push_back(Plane(Vector3.DOWN, -brush.mins.y))
			planes.push_back(Plane(Vector3.FORWARD, -brush.mins.z))

			var convex_points = Geometry3D.compute_convex_mesh_points(planes)
			if convex_points.size() < 3:
				print("Convex shape creation failed ", collision_index)
			else:
				var collision_shape := CollisionShape3D.new()
				collision_shape.name = "Collision%d" % collision_index
				for point_index in convex_points.size():
					convex_points[point_index] -= center
				var shape = ConvexPolygonShape3D.new()
				shape.points = convex_points
				collision_shape.shape = shape
				collision_shape.position = center
				collision_shape.transform = parent_inv_transform * collision_shape.transform
				body_to_add_to.add_child(collision_shape)
				collision_shape.owner = root_node

func build_collision_from_nodes(model_index, model_data, parent_node, parent_inv_transform):
	array_of_planes_array = []
	array_of_planes = []
	var bsp_model = model_data[model_index]

	var nodes_struct_size = (NODES_STRUCT_SIZE_Q1BSP if !is_bsp2 else NODES_STRUCT_SIZE_Q1BSP2)
	file.seek(nodes_offset + bsp_model.node_id0 * nodes_struct_size)
	read_nodes_recursive()

	var model_mins = bsp_model.bound_min
	var model_maxs = bsp_model.bound_max
	var model_mins_maxs_planes = [
		Plane(Vector3.RIGHT, model_maxs.x),
		Plane(Vector3.UP, model_maxs.y),
		Plane(Vector3.BACK, model_maxs.z),
		Plane(Vector3.LEFT, -model_mins.x),
		Plane(Vector3.DOWN, -model_mins.y),
		Plane(Vector3.FORWARD, -model_mins.z)
	]

	create_collision_shapes(parent_node, array_of_planes_array, model_mins_maxs_planes, parent_inv_transform)
	create_liquid_from_planes(parent_node, water_planes_array, model_mins_maxs_planes, parent_inv_transform, water_template)
	create_liquid_from_planes(parent_node, slime_planes_array, model_mins_maxs_planes, parent_inv_transform, slime_template)
	create_liquid_from_planes(parent_node, lava_planes_array, model_mins_maxs_planes, parent_inv_transform, lava_template)

func create_liquid_from_planes(parent_node : Node3D, planes_array : Array, model_mins_maxs_planes : Array[Plane], parent_inv_transform : Transform3D, template : PackedScene):
	if planes_array.size() > 0 and template:
		var liquid_body : Node = template.instantiate()
		parent_node.add_child(liquid_body, true)
		liquid_body.transform = parent_inv_transform
		liquid_body.owner = root_node
		create_collision_shapes(liquid_body, planes_array, model_mins_maxs_planes, Transform3D())

func create_collision_shapes(body : Node3D, planes_array, model_mins_maxs_planes, parent_inv_transform):
	for i in planes_array.size():
		var plane_indexes : PackedInt32Array = planes_array[i]
		var convex_planes : Array[Plane] = model_mins_maxs_planes.duplicate()
		for plane_index in plane_indexes:
			var pnorm = plane_normals[abs(plane_index)-1] * sign(plane_index)
			var pdist = plane_distances[abs(plane_index)-1] * sign(plane_index)
			var plane = Plane(pnorm, pdist)
			convex_planes.push_back(plane)

		var convex_points = Geometry3D.compute_convex_mesh_points(convex_planes)
		if convex_points.size() < 3:
			print("Convex shape creation failed ", i)
		else:
			var collision_shape = CollisionShape3D.new()
			collision_shape.name = "Collision%d" % i
			var center = Vector3.ZERO
			for point in convex_points:
				center += point
			center /= convex_points.size()

			if TEST_BOX_ONLY_COLLISION:
				var aabb = AABB(convex_points[0], Vector3.ZERO)
				for point in convex_points:
					aabb = aabb.expand(point)
				var box_shape = BoxShape3D.new()
				box_shape.size = abs(aabb.size)
				collision_shape.shape = box_shape
			else:
				var shape = ConvexPolygonShape3D.new()
				for point_index in convex_points.size():
					convex_points[point_index] -= center
				shape.points = convex_points
				collision_shape.shape = shape

			collision_shape.position = center
			collision_shape.transform = parent_inv_transform * collision_shape.transform
			if SINGLE_STATIC_BODY:
				body.add_child(collision_shape)
			else:
				var static_body = StaticBody3D.new()
				static_body.name = "StaticBody%d" % i
				static_body.transform = collision_shape.transform
				collision_shape.transform = Transform3D()
				body.add_child(static_body, true)
				static_body.owner = root_node
				static_body.add_child(collision_shape)
			collision_shape.owner = root_node

func read_nodes_recursive():
	var plane_index := file.get_32()
	var child0 := (unsigned16_to_signed(file.get_16()) if !is_bsp2 else unsigned32_to_signed(file.get_32()))
	var child1 := (unsigned16_to_signed(file.get_16()) if !is_bsp2 else unsigned32_to_signed(file.get_32()))

	array_of_planes.push_back(-(plane_index+1))
	handle_node_child(child0)
	array_of_planes.resize(array_of_planes.size() - 1)

	array_of_planes.push_back(plane_index+1)
	handle_node_child(child1)
	array_of_planes.resize(array_of_planes.size() - 1)

func handle_node_child(child_value : int):
	if child_value < 0:
		var leaf_id := ~child_value
		var leaf_size = (LEAF_SIZE_Q1BSP if !is_bsp2 else LEAF_SIZE_BSP2)
		var file_offset = leaves_offset + leaf_id * leaf_size
		file.seek(file_offset)
		var leaf_type := unsigned32_to_signed(file.get_32())
		match leaf_type:
			CONTENTS_SOLID:
				array_of_planes_array.push_back(array_of_planes.duplicate())
			CONTENTS_WATER:
				water_planes_array.push_back(array_of_planes.duplicate())
			CONTENTS_SLIME:
				slime_planes_array.push_back(array_of_planes.duplicate())
			CONTENTS_LAVA:
				lava_planes_array.push_back(array_of_planes.duplicate())
	else:
		var nodes_struct_size = (NODES_STRUCT_SIZE_Q1BSP if !is_bsp2 else NODES_STRUCT_SIZE_Q1BSP2)
		file.seek(nodes_offset + child_value * nodes_struct_size)
		read_nodes_recursive()

func read_model_data_q1_bsp(model_data : BSPModelData):
	var mins = read_vector_convert_scaled()
	var maxs = read_vector_convert_scaled()
	model_data.bound_min = Vector3(min(mins.x, maxs.x), min(mins.y, maxs.y), min(mins.z, maxs.z))
	model_data.bound_max = Vector3(max(mins.x, maxs.x), max(mins.y, maxs.y), max(mins.z, maxs.z))
	model_data.bound_min -= Vector3(_unit_scale, _unit_scale, _unit_scale)
	model_data.bound_max += Vector3(_unit_scale, _unit_scale, _unit_scale)
	model_data.origin = read_vector_convert_scaled()
	model_data.node_id0 = file.get_32()
	model_data.node_id1 = file.get_32()
	model_data.node_id2 = file.get_32()
	model_data.node_id3 = file.get_32()
	model_data.num_leafs = file.get_32()
	model_data.face_index = file.get_32()
	model_data.face_count = file.get_32()

func read_vector_convert_scaled() -> Vector3:
	return convert_vector_from_quake_scaled(Vector3(file.get_float(), file.get_float(), file.get_float()), _unit_scale)

func load_or_create_material(name : StringName, bsp_texture : BSPTexture = null) -> MaterialInfo:
	var width := 0
	var height := 0
	var material : Material = null
	if bsp_texture:
		width = bsp_texture.width
		height = bsp_texture.height

	var material_path : String
	if texture_material_rename.has(name):
		material_path = texture_material_rename[name]
	else:
		material_path = material_path_pattern.replace("{texture_name}", name)

	var image_path : String
	var texture : Texture2D = null
	var texture_emission : Texture2D = null
	var need_to_save_image := false

	if texture_path_remap.has(name):
		image_path = texture_path_remap[name]
	else:
		image_path = texture_path_pattern.replace("{texture_name}", name)
	var original_image_path = image_path
	if !ResourceLoader.exists(image_path):
		image_path = str(image_path.get_basename(), ".jpg")

	if ResourceLoader.exists(image_path):
		texture = load(image_path)
		if texture:
			width = texture.get_width()
			height = texture.get_height()
	else:
		print("Could not load ", original_image_path)

	var image_emission_path = texture_emission_path_pattern.replace("{texture_name}", name)
	if ResourceLoader.exists(image_emission_path):
		texture_emission = load(image_emission_path)

	if ResourceLoader.exists(material_path) and !overwrite_existing_materials:
		material = load(material_path)
		if (width == 0 or height == 0) and material:
			if material is BaseMaterial3D:
				texture = material.albedo_texture
			elif material is ShaderMaterial:
				var params_to_check = ["albedo_texture","texture_albedo","texture","albedo","texture_diffuse"]
				for param_name in params_to_check:
					var test = material.get_shader_parameter(param_name)
					if test is Texture2D:
						texture = test
						break
			if texture:
				width = texture.get_width()
				height = texture.get_height()
	else:
		# Create material
		material = StandardMaterial3D.new()
		if texture:
			material.albedo_texture = texture
		if texture_emission:
			material.emission_enabled = true
			material.emission_texture = texture_emission
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

		if save_separate_materials:
			if texture:
				var image_dir = image_path.get_base_dir()
				if !DirAccess.dir_exists_absolute(image_dir):
					DirAccess.make_dir_recursive_absolute(image_dir)

				if !ResourceLoader.exists(image_path):
					# If we had raw image data we would save it here.
					# This code is simplified, but in original it would save the generated image.
					# image.save_png(image_path)
					material.albedo_texture.resource_path = image_path

				if texture_emission and !ResourceLoader.exists(image_emission_path):
					# image_emission.save_png(image_emission_path)
					material.emission_texture.resource_path = image_emission_path

				var material_dir = material_path.get_base_dir()
				if !DirAccess.dir_exists_absolute(material_dir):
					DirAccess.make_dir_recursive_absolute(material_dir)
				ResourceSaver.save(material, material_path)
				material.take_over_path(material_path)
		else:
			if !texture:
				material.albedo_color = Color(randf(), randf(), randf())

	var material_info = MaterialInfo.new()
	material_info.material = material
	material_info.width = width
	material_info.height = height
	return material_info

# CSLR's Q2BSP importer code -- probably lots of redundant stuff here that should be merged into a common code path.

enum {LUMP_OFFSET, LUMP_LENGTH}

enum Q2 {
	LUMP_ENT,
	LUMP_PLANE,
	LUMP_VERTEX,
	LUMP_VIS,
	LUMP_NODE,
	LUMP_TEXTURE,
	LUMP_FACE,
	LUMP_LIGHTMAP,
	LUMP_LEAVES,
	LUMP_LEAF_FACE_TABLE,
	LUMP_LEAF_BRUSH_TABLE,
	LUMP_EDGE,
	LUMP_FACE_EDGE,
	LUMP_MODEL,
	LUMP_BRUSH,
	LUMP_BRUSH_SIDE
}


var geometry := {}
var textures := {}

var entities := []

var models := []

class BSPEntity extends Node3D:
	var default_class_data : Dictionary = {}
	func updatename() -> void: if default_class_data.has("classname"): self.name = default_class_data.get("classname")

class BSPPlane:
	var normal := Vector3.ZERO
	var distance : float = 0
	var type : int = 0 # ? 

class BSPBrush:
	var first_brush_side : int = 0
	var num_brush_side : int = 0
	var flags : int = 0

class BSPBrushSide:
	var plane_index : int = 0
	var texture_information : int = 0
	
func convertBSP2toScene(file_path : String) -> Node:

	prints("Converting File", file_path, ". Please Keep in Mind This is Still in Development and has some issues.")
	
	var file_name = file_path.get_base_dir()
	
	var CenterNode = StaticBody3D.new()
	var MeshInstance = convert_to_mesh(file_path) 
	var CollisionShape = CollisionShape3D.new()
	
	var cnn = str("BSPi2_", file_path.get_basename().trim_prefix(file_path.get_base_dir())).replace("/", "")
	CenterNode.name = cnn
	
	CenterNode.add_child(MeshInstance)
	
	MeshInstance.owner = CenterNode
	
	var collisions = create_collisions()
	
	for collision in collisions:
		var cs = CollisionShape3D.new()
		CenterNode.add_child(cs)
		cs.owner = CenterNode
		cs.shape = collision
		cs.name = str('brush', RID(collision).get_id())
	
	CenterNode.set_collision_layer_value(2, true)
	CenterNode.set_collision_mask_value(2, true)

	place_entities(entities, CenterNode)
	
	return CenterNode
	
## Central Function
func convert_to_mesh(file):
	var bsp_bytes : PackedByteArray = FileAccess.get_file_as_bytes(file)
	
	var bsp_version = str(convert_from_uint32(bytes(bsp_bytes, range(4, 8))))
	var magic_num = bytes(bsp_bytes, range(0, 4)).get_string_from_utf8()
	
	prints("Found BSP Version %s %s, Expecting Version IBSP 38" % [magic_num, bsp_version])
	
	var directory = fetch_directory(bsp_bytes)
	
	# i regret this code!
	var plane_lmp = range(directory[LUMP_PLANE].get(LUMP_OFFSET), directory[LUMP_PLANE].get(LUMP_OFFSET)+directory[LUMP_PLANE].get(LUMP_LENGTH))
	
	
	var vertex_lmp = range(directory[Q2.LUMP_VERTEX].get(LUMP_OFFSET), directory[Q2.LUMP_VERTEX].get(LUMP_OFFSET)+directory[Q2.LUMP_VERTEX].get(LUMP_LENGTH))
	var face_edge_lmp = range(directory[Q2.LUMP_FACE_EDGE].get(LUMP_OFFSET), directory[Q2.LUMP_FACE_EDGE].get(LUMP_OFFSET)+directory[Q2.LUMP_FACE_EDGE].get(LUMP_LENGTH))
	
	var face_lmp = range(directory[Q2.LUMP_FACE].get(LUMP_OFFSET), directory[Q2.LUMP_FACE].get(LUMP_OFFSET)+directory[Q2.LUMP_FACE].get(LUMP_LENGTH))
	var edge_lmp = range(directory[Q2.LUMP_EDGE].get(LUMP_OFFSET), directory[Q2.LUMP_EDGE].get(LUMP_OFFSET)+directory[Q2.LUMP_EDGE].get(LUMP_LENGTH))
	
	var texture_lmp = range(directory[Q2.LUMP_TEXTURE].get(LUMP_OFFSET), directory[Q2.LUMP_TEXTURE].get(LUMP_OFFSET)+directory[Q2.LUMP_TEXTURE].get(LUMP_LENGTH))
	var entity_lmp = range(directory[Q2.LUMP_ENT].get(LUMP_OFFSET), directory[Q2.LUMP_ENT].get(LUMP_OFFSET)+directory[Q2.LUMP_ENT].get(LUMP_LENGTH))
	
	var model_lmp = range(directory[Q2.LUMP_MODEL].get(LUMP_OFFSET), directory[Q2.LUMP_MODEL].get(LUMP_OFFSET)+directory[Q2.LUMP_MODEL].get(LUMP_LENGTH))

	var brush_lmp = range(directory[Q2.LUMP_BRUSH].get(LUMP_OFFSET), directory[Q2.LUMP_BRUSH].get(LUMP_OFFSET)+directory[Q2.LUMP_BRUSH].get(LUMP_LENGTH))
	var brush_side_lmp = range(directory[Q2.LUMP_BRUSH_SIDE].get(LUMP_OFFSET), directory[Q2.LUMP_BRUSH_SIDE].get(LUMP_OFFSET)+directory[Q2.LUMP_BRUSH_SIDE].get(LUMP_LENGTH))
	
	
	entities = process_entity_lmp(bytes(bsp_bytes, entity_lmp))
	
	
	models = get_models(bytes(bsp_bytes, model_lmp))
	
	geometry = {}
	textures = {}
	geometry["plane"] = get_planes(bytes(bsp_bytes, plane_lmp))
	geometry["vertex"] = get_verts(bytes(bsp_bytes, vertex_lmp))
	geometry["face"] = get_face_lump(bytes(bsp_bytes, face_lmp))
	
	geometry["edge"] = get_edges(bytes(bsp_bytes, edge_lmp))
	geometry["face_edge"] = get_face_edges(bytes(bsp_bytes, face_edge_lmp))
	
	geometry["brush"] = get_brushes(bytes(bsp_bytes, brush_lmp))
	geometry["brush_side"] = get_brush_sides(bytes(bsp_bytes, brush_side_lmp))
	
	textures["lumps"] = get_texture_lmp(bytes(bsp_bytes, texture_lmp))
	
	
	process_to_mesh_array(geometry)
	
	var mesh := create_mesh(geometry["face"])
	var mi := MeshInstance3D.new()
	var arm := ArrayMesh.new()
	
	
	for surface in mesh.get_surface_count():
		arm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
		arm.surface_set_material(surface, mesh.surface_get_material(surface))
	
	mi.mesh = arm
	
	return mi


func place_entities(entities : Array, owner_node):
	var world_node = Node3D.new(); 
	owner_node.add_child(world_node)
	world_node.name = str("WorldObjects"); 
	world_node.owner = owner_node
	
	var spawn_nodes = Node3D.new()
	world_node.add_child(spawn_nodes)
	spawn_nodes.name = str("Spawns")
	spawn_nodes.owner = owner_node
	
	var weapon_spawns = Node3D.new()
	spawn_nodes.add_child(weapon_spawns)
	weapon_spawns.name = str("Weapons")
	weapon_spawns.owner = owner_node
	 
	for entity in entities:
		entity = entity as BSPEntity
		
		
		if entity.default_class_data.get("classname") == "weapon_pballgun":
			var weapon_node = Node3D.new()
			var vector_pos = origin_to_vec(entity.default_class_data.get("origin"))
			weapon_spawns.add_child(weapon_node)
			weapon_node.name = str("weapon_pballgun_", entity.default_class_data.get("type"))
			weapon_node.owner = owner_node
			weapon_node.transform.origin = vector_pos
		
		if entity.default_class_data.get("classname") == "info_player_deathmatch" and entity.default_class_data.has("teamnumber"):
			var team_names = ["TeamRed", "TeamBlue"]
			var team = str(entity.default_class_data.get("teamnumber")).to_int()-1
			var team_name = team_names[wrapi(team, 0, 2)]
			
			if not spawn_nodes.has_node(team_name):
				var n = Node3D.new()
				n.name = str(team_name)
				
				spawn_nodes.add_child(n)
				n.owner = owner_node

			if spawn_nodes.has_node(team_name):
				var vector_pos = origin_to_vec(entity.default_class_data.get("origin"))
				
				var spawn_node = Node3D.new()
				spawn_nodes.get_node(team_name).add_child(spawn_node)
				spawn_node.owner = owner_node
				spawn_node.transform.origin = vector_pos# / 32.0

	return world_node

func origin_to_vec(origin : String) -> Vector3:
	var v = Vector3.ZERO
	var pos = origin.split(" ")
	var vec = Vector3(pos[0].to_int(), pos[1].to_int(), pos[2].to_int())
	v = BSPReader.new().convert_vector_from_quake_unscaled(vec)
	return v

## takes the vertex, face, edge and face edge arrays and outputs an array of all the edge points.
func process_to_mesh_array(geometry : Dictionary) -> void:
	var output_verts = []
	var face_vertex_indices = []
	
	var verts = geometry.get("vertex")
	var edges = geometry.get("edge")
	var face_edges = geometry.get("face_edge")
	
	for face_index in geometry.get("face"):
		var face = face_index as BSPFace
		var first_edge = face.edge_list_id
		var num_edges = face.num_edges
		
		var edge_range = range(first_edge, first_edge + num_edges)
		
		var face_vert_list = []
		var face_vert_out = []
		
		for edge in edge_range:
			
			var face_edge = face_edges[edge]
			
			edge = edges[abs(face_edge)]
			
			var edge0 = edge[0]
			var edge1 = edge[1]
			
			if face_edge > 0:
				edge0 = edge[0]
				edge1 = edge[1]
			
			if face_edge < 0:
				edge0 = edge[1]
				edge1 = edge[0]
 			
			
			
			var vert0 = verts[edge0]
			var vert1 = verts[edge1]
			
			face_vert_list.append_array([vert0, vert1])
			
		
		for v in range(0, face_vert_list.size()-2):
			
			var vert0 = face_vert_list[0]
			var vert1 = face_vert_list[v + 1]
			var vert2 = face_vert_list[v + 2]
			
			face_vert_out.append(vert2)
			face_vert_out.append(vert1)
			face_vert_out.append(vert0)
		
		face.verts = face_vert_out

func process_entity_lmp(ent_bytes : PackedByteArray):
	prints("a unicode passing error may accur, this is 'normal'.")
	var entities = process_json(ent_bytes.get_string_from_utf8())
	var entity_output = []
	if !entities:
		return entity_output
		
	var entity_list = entities.get("data")
	
	for entity in entity_list:
		if entity is Dictionary:
			var entityNode = BSPEntity.new()
			if entity.has("classname") and ClassDB.class_exists(entity.get("classname")):
				entityNode = ClassDB.instantiate(entity.get("classname"))
			else:
				entityNode.default_class_data = entity
			entityNode.updatename()
			entity_output.append(entityNode)
	
	return entity_output

func process_json(string):
	var replaced_string = string.replace('" "', '":"').replace('"\n', '",\n').replace("}", "},")
	replaced_string = str('{"data":[', replaced_string, "]}")
	return JSON.parse_string(replaced_string)


## grabs the directory
func fetch_directory(bsp_bytes):
	prints("QBSPi2 BSP File Size:", bsp_bytes.size())
	var i = 0
	var dir = {}
	var dir_lump = bytes( bsp_bytes, range(8, ( 19 * 8 ) ))
	
	for lump in range(0, dir_lump.size()-8, 8):
		
		var offset = bytes(dir_lump, range(lump+0, lump+4)).decode_u32(0)
		var length = bytes(dir_lump, range(lump+4, lump+8)).decode_u32(0)
		
		dir[lump / 8] = {LUMP_OFFSET: offset, LUMP_LENGTH: length}
		
		
	return dir

func get_planes(plane_bytes : PackedByteArray) -> Array[BSPPlane]:
	var planes : Array[BSPPlane] = []
	var count = plane_bytes.size() / 20
	if randi_range(0, 1000000) == 10284: 
		print("QBSPi2 Calculated Estimate of %s Planes, hopefully no towers are around...." % count) # why did i push this to github?
	else: 
		print("QBSPi2 Calculated Estimate of %s Planes." % count)
	
	for index in range(0, plane_bytes.size(), 20):
		var norm_x = bytes(plane_bytes, range(index + 0, index + 4)).decode_float(0)
		var norm_y = bytes(plane_bytes, range(index + 4, index + 8)).decode_float(0)
		var norm_z = bytes(plane_bytes, range(index + 8, index + 12)).decode_float(0)
		
		var distance = bytes(plane_bytes, range(index + 12, index + 16)).decode_float(0)
		
		var type = bytes(plane_bytes, range(index + 16, index + 20)).decode_u32(0)
		
		var plane = BSPPlane.new()
		plane.normal = Vector3(-norm_y, norm_z, -norm_x)
		plane.distance = distance
		plane.type = type
		planes.append(plane)
	return planes


func get_brushes(brush_bytes : PackedByteArray):
	var count = brush_bytes.size() / 12
	print("QBSPi2 Calculated Estimate of %s Brushes" % count)
	var brushes = []
	for index in range(0, brush_bytes.size(), 12):
		var brush = BSPBrush.new()
		var first_brush_side = bytes(brush_bytes, range(index + 0, index + 4)).decode_u32(0)
		var num_brush_side = bytes(brush_bytes, range(index + 4, index + 8)).decode_u32(0)
		var flags = bytes(brush_bytes, range(index + 8, index + 10)).decode_u16(0) 
		#var flags2 = bytes(brush_bytes, range(index + 10, index + 12)).decode_u16(0) 
		
		brush.first_brush_side = first_brush_side
		brush.num_brush_side = num_brush_side
		brush.flags = flags
		
		
		brushes.append(brush)
	return brushes

func get_brush_sides(brush_side_bytes : PackedByteArray):
	var count = brush_side_bytes.size() / 4
	print("QBSPi2 Calculated Estimate of %s Brush Sides" % count)
	var brush_sides = []
	for index in range(0, brush_side_bytes.size(), 4):
		
		var plane_index = bytes(brush_side_bytes, range(index + 0, index + 2)).decode_u16(0)
		var texture_information = bytes(brush_side_bytes, range(index + 2, index + 4)).decode_s16(0)
		
		var brush_side = BSPBrushSide.new()
		
		
		brush_side.plane_index = plane_index
		brush_side.texture_information = texture_information
		
		brush_sides.append(brush_side)
	return brush_sides

## returns vertex lump
func get_verts(vert_bytes : PackedByteArray) -> PackedVector3Array:
	var count = vert_bytes.size() / 12
	var vertex_array : PackedVector3Array = []
	print("QBSPi2 Calculated Estimate of %s Vertices" % count)
	
	var v = 0
	while v < count:
		
		var xbytes = bytes(vert_bytes, range( (v * 12), (v * 12) + 4 )).decode_float(0)
		var ybytes = bytes(vert_bytes, range( (v * 12) + 4, (v * 12) + 8 )).decode_float(0)
		var zbytes = bytes(vert_bytes, range( (v * 12) + 8, (v * 12) + 12 )).decode_float(0)
		
		var vec = Vector3(-ybytes, zbytes, -xbytes)
		vertex_array.append(vec)
		v += 1
	return vertex_array

## returns face lump
func get_face_lump(lump_bytes : PackedByteArray):
	var count = lump_bytes.size() / 20
	prints("QBSPi2 Calculated Estimate of %s Faces" % count)
	var faces : Array[BSPFace] = []
	var f = 0
	
	while f < count:
		var new_face := BSPFace.new()
		var base_index = f * 20
		
		var by = bytes(lump_bytes, range(base_index, base_index + 20))
		
		new_face.plane_id     = by.decode_u16(0)
		new_face.plane_side   = by.decode_u16(2)
		new_face.edge_list_id = by.decode_u32(4)
		new_face.num_edges    = by.decode_u16(8)
		new_face.texinfo_id   = by.decode_u16(10)
		
		faces.append(new_face)
		f += 1
	
	return faces


## returns texture lump
func get_texture_lmp(tex_bytes : PackedByteArray) -> Array:
	var count = tex_bytes.size() / 76
	prints("QBSPi2 Calculated Estimate of %s Texture References" % count)
	
	var output = []
	
	for b in range(0, tex_bytes.size(), 76):
		var BSPTI := BSPTextureInfo.new()
		
		var ux = bytes(tex_bytes, range(b, b + 4)).decode_float(0)
		var uy = bytes(tex_bytes, range(b + 4, b + 8)).decode_float(0)
		var uz = bytes(tex_bytes, range(b + 8, b + 12)).decode_float(0)
		
		var uoffset = bytes(tex_bytes, range(b + 12, b + 16)).decode_float(0)
		
		var vx = bytes(tex_bytes, range(b + 16, b + 20)).decode_float(0)
		var vy = bytes(tex_bytes, range(b + 20, b + 24)).decode_float(0)
		var vz = bytes(tex_bytes, range(b + 24, b + 28)).decode_float(0)
		
		var voffset = bytes(tex_bytes, range(b + 28, b + 32)).decode_float(0)
		
		var flags = bytes(tex_bytes, range(b + 32, b + 36)).decode_u32(0)
		var value = bytes(tex_bytes, range(b + 36, b + 40)).decode_u32(0)
		
		var texture_path = bytes(tex_bytes, range(b + 40, b + 72)).get_string_from_utf8()
		
		var next_texinfo = bytes(tex_bytes, range(b + 72, b + 76)).decode_s32(0)
		
		BSPTI.vec_s = convert_vector_from_quake_unscaled(Vector3(ux, uy, uz))
		BSPTI.offset_s = uoffset
		BSPTI.vec_t = convert_vector_from_quake_unscaled(Vector3(vx, vy, vz))
		BSPTI.offset_t = voffset
		BSPTI.flags = flags
		BSPTI.value = value
		BSPTI.texture_path = texture_path
		#BSPTI.next_textinfo = next_texinfo
		
		#BSPTI.name = str(BSPTI.texture_path)
		
		output.append(BSPTI)
		
	
	return output

## returns edge lump
func get_edges(edge_bytes : PackedByteArray):
	var count = edge_bytes.size() / 4
	var e = 0
	var edges = []
	while e < count:
		var index = e * 4
		var edge_1 = bytes(edge_bytes, range(index + 0, index + 2)).decode_u16(0)
		var edge_2 = bytes(edge_bytes, range(index + 2, index + 4)).decode_u16(0)
		
		
		edges.append([edge_1, edge_2])
		e += 1
	
	return edges


## returns face edge lump
func get_face_edges(face_bytes : PackedByteArray):
	var count = face_bytes.size() / 4
	prints("QBSPi2 Calculated Estimate of %s Face Edges" % count)
	var f = 0
	var face_edges = []
	while f < count:
		var index = f * 4 
		var f1 = bytes(face_bytes, range(index + 0, index + 4)).decode_s32(0)
		face_edges.append(f1)
		f += 1
	
	return face_edges

## i dont know what models are used for but if someone could tell me that would be good.
func get_models(model_bytes : PackedByteArray):
	var count = model_bytes.size() / 48
	prints("QBSPi2 Calculated Estimate of %s Models" % count)
	
	for m in range(0, model_bytes.size(), 48):
		var a1 = bytes(model_bytes, range(m + 0, m + 4)).decode_float(0)
		var a2 = bytes(model_bytes, range(m + 4, m + 8)).decode_float(0)
		var b1 = bytes(model_bytes, range(m + 8, m + 12)).decode_float(0)
		var b2 = bytes(model_bytes, range(m + 12, m + 16)).decode_float(0)
		var c1 = bytes(model_bytes, range(m + 16, m + 20)).decode_float(0)
		var c2 = bytes(model_bytes, range(m + 20, m + 24)).decode_float(0)
		
		var ox = bytes(model_bytes, range(m + 24, m + 28)).decode_float(0)
		var oy = bytes(model_bytes, range(m + 28, m + 32)).decode_float(0)
		var oz = bytes(model_bytes, range(m + 32, m + 36)).decode_float(0)
		
		var head = bytes(model_bytes, range(m + 36, m + 40)).decode_s32(0)
		
		var first_face = bytes(model_bytes, range(m + 40, m + 44)).decode_u32(0)
		var num_faces = bytes(model_bytes, range(m + 44, m + 48)).decode_u32(0)
		
	return []

func create_collisions():
	var collisions = []
	var final_verts = []
	for brush in geometry["brush"]:
		var brush_planes : Array[Plane] = []
		brush = brush as BSPBrush
		var brush_side_range = range(brush.first_brush_side, (brush.first_brush_side + brush.num_brush_side))
		#print(brush.flags)
		
		if brush.flags == 1:
			for brush_side_index in brush_side_range:
				var brush_side = geometry["brush_side"][brush_side_index]
				var plane = geometry["plane"][brush_side.plane_index] as BSPPlane
				
				var plane_vec = Plane(plane.normal, plane.distance / 32.0)
				
				brush_planes.append(plane_vec)
			
			var verts = Geometry3D.compute_convex_mesh_points(brush_planes)
			var collision = ConvexPolygonShape3D.new()
			
			collision.set_points(verts)
			collisions.append(collision)
	
	return collisions

func create_mesh(face_data : Array[BSPFace]) -> Mesh:
	var mesh = ArrayMesh.new()
	var texture_list = textures["lumps"]
	var surface_list := {}
	var material_info_lookup := {}
	var missing_textures := []
	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	
	for texture in texture_list:
		texture = texture as BSPTextureInfo
		
		if not surface_list.has(texture.texture_path):
			var st =  SurfaceTool.new()
			surface_list[texture.texture_path] = st
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for face in face_data:
		var texture : BSPTextureInfo = textures["lumps"][face.texinfo_id]
		
		if surface_list.has(texture.texture_path):
			var surface_tool : SurfaceTool = surface_list.get(texture.texture_path)
			var material_info : MaterialInfo = material_info_lookup.get(surface_tool, null)
			if (!material_info):
				material_info = load_or_create_material(texture.texture_path)
				material_info_lookup[surface_tool] = material_info
			var material := material_info.material
			var width := material_info.width
			var height := material_info.height
			var verts : PackedVector3Array = face.verts
			if not material.albedo_color.a == 0: # TODO: Check flags instead (Don't make mesh for skip or sky flags)
				for vertIndex in range(0, verts.size(), 3):
					var v0 = verts[vertIndex + 0]
					var v1 = verts[vertIndex + 1]
					var v2 = verts[vertIndex + 2]
					
					var uv0 = get_uv_q(v0, texture, width, height)
					var uv1 = get_uv_q(v1, texture, width, height)
					var uv2 = get_uv_q(v2, texture, width, height)
					
					var plane = geometry["plane"][face.plane_id] as BSPPlane
					#var normal : Vector3 = (v1 - v0).cross((v2 - v0))
					var normal : Vector3 = plane.normal
					
					surface_tool.set_material(material)
					surface_tool.set_normal(normal.normalized())
					surface_tool.set_uv(uv2)
					surface_tool.add_vertex(v2 / 32.0)
					surface_tool.set_uv(uv1)
					surface_tool.add_vertex(v1 / 32.0)
					surface_tool.set_uv(uv0)
					surface_tool.add_vertex(v0 / 32.0)

	for tool in surface_list.values():
		tool = tool as SurfaceTool
		mesh = tool.commit(mesh) as ArrayMesh
	prints("\n\n\n QBSPi2 - Completed Mesh With %s Surfaces" % mesh.get_surface_count())
	if missing_textures.size() > 0: prints(".\nMissing Textures:", missing_textures, "Some Faces may be invisible, Trust me they're there the surface albedo is just 0!")
	return mesh


func get_uv_q(vertex : Vector3, tex_info : BSPTextureInfo, width : float, height : float) -> Vector2:
	var u := (vertex.dot(tex_info.vec_s) + tex_info.offset_s) / width
	var v := (vertex.dot(tex_info.vec_t) + tex_info.offset_t) / height
	return Vector2(u, v)


## converts 2 bytes to a unsigned int16
func convert_from_uint16(uint16):
	var uint16_value = uint16.decode_u16(0)
	if uint16.size() < 4: return 0
	return uint16_value


## converts 4 bytes to a unsigned int32
func convert_from_uint32(uint32 : PackedByteArray):
	var uint32_value = uint32.decode_u32(0)
	if uint32.size() < 4: return 0
	return uint32_value


## returns bytes, indices should be an array e.g. [1, 2, 3, 4]
func bytes(input_array, indices : Array) -> PackedByteArray:
	var output_array = []
	for index in indices:
		output_array.append(input_array[index])
	return output_array

# Helper function to read a lump into memory
func get_lump_data(lumps, lump_index: int) -> PackedByteArray:
	var off = lumps[lump_index]["offset"]
	var length = lumps[lump_index]["length"]
	file.seek(off)
	return file.get_buffer(length)
	
# Q3BSP Logic

enum Q3 {
	# Quake 3 Lumps (for IBSP 46/47)
	LUMP_ENTITIES,
	LUMP_TEXTURES,
	LUMP_PLANES,
	LUMP_NODES,
	LUMP_LEAFS,
	LUMP_LEAF_FACES,
	LUMP_LEAF_BRUSHES,
	LUMP_MODELS,
	LUMP_BRUSHES,
	LUMP_BRUSH_SIDES,
	LUMP_VERTICES,
	LUMP_MESHVERTS,
	LUMP_EFFECTS,
	LUMP_FACES,
	LUMP_LIGHTMAPS,
	LUMP_LIGHTVOLS,
	LUMP_VISDATA,
}

const Q3_NUM_LUMPS = 17

func convertBSP3toScene(file_path: String):
	
	prints("Converting File", file_path, ". Please Keep in Mind This is Still in Development and has some issues.")
	
	var file_name = file_path.get_base_dir()
	print(file_name)
	
	var CenterNode = StaticBody3D.new()
	var MeshInstance = convert_q3_to_mesh(file_path) 
	var CollisionShape = CollisionShape3D.new()
	
	CenterNode.name = str("BSPi3_", file_path.get_basename().trim_prefix(file_path.get_base_dir())).replace("/", "")
	
	CenterNode.add_child(MeshInstance)
	
	MeshInstance.owner = CenterNode
	
	#var collisions = create_collisions()
	#
	#for collision in collisions:
		#var cs = CollisionShape3D.new()
		#CenterNode.add_child(cs)
		#cs.owner = CenterNode
		#cs.shape = collision
		#cs.name = str('brush', RID(collision).get_id())
	#
	#CenterNode.set_collision_layer_value(2, true)
	#CenterNode.set_collision_mask_value(2, true)

	# place_entities(entities, CenterNode)
	
	return CenterNode

func convert_q3_to_mesh(file_path: String) -> MeshInstance3D:
	# Quake 3 lumps reading:
	# After reading magic (IBSP) and version (46 or 47), the next 17 lumps follow.
	var q3_lumps = []
	q3_lumps.resize(Q3_NUM_LUMPS)
	for i in range(Q3_NUM_LUMPS):
		var lump_offset = file.get_32()
		var lump_length = file.get_32()
		q3_lumps[i] = { "offset": lump_offset, "length": lump_length }
	
	# Now we have all Q3 lumps in q3_lumps.
	# Quake 3 lumps:
	#  0: Entities
	#  1: Shaders/Textures
	#  2: Planes
	#  3: Nodes
	#  4: Leafs
	#  5: Leaf Faces
	#  6: Leaf Brushes
	#  7: Models
	#  8: Brushes
	#  9: Brush Sides
	# 10: Vertices
	# 11: Meshverts
	# 12: Effects
	# 13: Faces
	# 14: Lightmaps
	# 15: Lightvols
	# 16: Visdata

	# Extract entities
	var entities_offset = q3_lumps[Q3.LUMP_ENTITIES]["offset"]
	var entities_length = q3_lumps[Q3.LUMP_ENTITIES]["length"]
	file.seek(entities_offset)
	var entity_string = file.get_buffer(entities_length).get_string_from_utf8()
	var entity_dict_array = parse_entity_string(entity_string)
	convert_entity_dict_to_scene(entity_dict_array)

	# Extract textures (shaders)
	var shaders_offset = q3_lumps[Q3.LUMP_TEXTURES]["offset"]
	var shaders_length = q3_lumps[Q3.LUMP_TEXTURES]["length"]
	# Read and store shader info from Q3 BSP. Each shader entry is 64 bytes (name 64 chars) + 4 bytes surface flags + 4 bytes content flags in standard Q3.
	var shaders = read_q3_shaders(file, shaders_offset, shaders_length)

	# Extract planes
	var planes_offset = q3_lumps[Q3.LUMP_PLANES]["offset"]
	var planes_length = q3_lumps[Q3.LUMP_PLANES]["length"]
	# Each plane in Q3 BSP: 16 bytes (3 floats for normal + 1 float for dist).
	var planes = read_q3_planes(file, planes_offset, planes_length)

	# Extract vertices
	var vertices_offset = q3_lumps[Q3.LUMP_VERTICES]["offset"]
	var vertices_length = q3_lumps[Q3.LUMP_VERTICES]["length"]
	# Q3 vertex: struct of (x,y,z), (st[0], st[1]), (lm_st[0], lm_st[1]), normal(3 floats), color(4 bytes)
	var vertices = read_q3_vertices(file, vertices_offset, vertices_length)

	# Extract faces
	var faces_offset = q3_lumps[Q3.LUMP_FACES]["offset"]
	var faces_length = q3_lumps[Q3.LUMP_FACES]["length"]
	# Q3 face structure differs significantly from Q1/Q2. 
	var faces = read_q3_faces(file, faces_offset, faces_length)
	
	# Extract meshverts
	var meshverts_offset = q3_lumps[Q3.LUMP_MESHVERTS]["offset"]
	var meshverts_length = q3_lumps[Q3.LUMP_MESHVERTS]["length"]
	var meshvert_count = meshverts_length / 4
	file.seek(meshverts_offset)
	var meshverts = PackedInt32Array()
	meshverts.resize(meshvert_count)
	for i in range(meshvert_count):
		meshverts[i] = file.get_32()

	# After reading the lumps and data:
	# Construct geometry, load materials/shaders, create mesh from Q3 faces.
	return build_q3_geometry(planes, vertices, faces, meshverts, shaders, 0.1)
	
func read_q3_shaders(file: FileAccess, offset: int, length: int) -> Array:
	var shaders = []
	file.seek(offset)
	var count = length / 72

	for i in range(count):
		# Read 64-byte name
		var name_bytes = file.get_buffer(64)
		var name_str = name_bytes.get_string_from_ascii()
		# Shader names may be null-terminated and padded
		# Strip everything after the first '\0', if any
		var null_pos = name_str.find('\\0')
		if null_pos != -1:
			name_str = name_str.substr(0, null_pos)
		name_str = name_str.strip_edges()

		var surface_flags = file.get_32()
		var content_flags = file.get_32()

		shaders.append({
			"name": name_str,
			"surface_flags": surface_flags,
			"content_flags": content_flags
		})

	return shaders

func read_q3_planes(file: FileAccess, offset: int, length: int) -> Array:
	var planes = []
	file.seek(offset)
	var count = length / 16
	for i in range(count):
		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var dist = file.get_float()
		# Convert from Quake's coordinate system to Godot's
		var normal = convert_vector_from_quake_unscaled(Vector3(nx, ny, nz))
		planes.append({
			"normal": normal,
			"distance": dist
		})
	return planes

func read_q3_vertices(file: FileAccess, offset: int, length: int) -> Array:
	var vertices = []
	file.seek(offset)
	var count = length / 44

	for i in range(count):
		var px = file.get_float()
		var py = file.get_float()
		var pz = file.get_float()
		var stx = file.get_float()
		var sty = file.get_float()
		var lmx = file.get_float()
		var lmy = file.get_float()
		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var c_r = file.get_8()
		var c_g = file.get_8()
		var c_b = file.get_8()
		var c_a = file.get_8()

		var position = convert_vector_from_quake_unscaled(Vector3(px, py, pz))
		var normal = convert_vector_from_quake_unscaled(Vector3(nx, ny, nz))
		# Convert color bytes [0..255] to float [0..1]
		var color = Color(c_r/255.0, c_g/255.0, c_b/255.0, c_a/255.0)

		vertices.append({
			"position": position,
			"uv": Vector2(stx, sty),
			"lm_uv": Vector2(lmx, lmy),
			"normal": normal,
			"color": color
		})
	return vertices

func read_q3_faces(file: FileAccess, offset: int, length: int) -> Array:
	var faces: Array[Dictionary] = []
	file.seek(offset)
	var count = length / 104

	for i in range(count):
		var texture = file.get_32()
		var effect = file.get_32()
		var ftype = file.get_32()
		var firstVert = file.get_32()
		var numVerts = file.get_32()
		var firstMeshvert = file.get_32()
		var numMeshverts = file.get_32()
		var lm_index = file.get_32()
		var lm_start_s = file.get_32()
		var lm_start_t = file.get_32()
		var lm_size_w = file.get_32()
		var lm_size_h = file.get_32()

		var lm_origin_x = file.get_float()
		var lm_origin_y = file.get_float()
		var lm_origin_z = file.get_float()

		var lm_vecs = []
		for v_i in range(2):
			var vx = file.get_float()
			var vy = file.get_float()
			var vz = file.get_float()
			lm_vecs.append(convert_vector_from_quake_unscaled(Vector3(vx, vy, vz)))

		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var normal = convert_vector_from_quake_unscaled(Vector3(nx, ny, nz))

		var size_w = file.get_32()
		var size_h = file.get_32()

		var lm_origin = convert_vector_from_quake_unscaled(Vector3(lm_origin_x, lm_origin_y, lm_origin_z))

		faces.append({
			"texture": texture,
			"effect": effect,
			"type": ftype,
			"first_vertex": firstVert,
			"num_vertices": numVerts,
			"first_meshvert": firstMeshvert,
			"num_meshverts": numMeshverts,
			"lm_index": lm_index,
			"lm_start": Vector2(lm_start_s, lm_start_t),
			"lm_size": Vector2(lm_size_w, lm_size_h),
			"lm_origin": lm_origin,
			"lm_vecs": lm_vecs,
			"normal": normal,
			"patch_size": Vector2(size_w, size_h)
		})
	return faces

func build_q3_geometry(planes: Array, vertices: Array, faces: Array, meshverts: PackedInt32Array, textures: Array, unit_scale: float = 1.0) -> MeshInstance3D:
	# Create a parent MeshInstance to hold the geometry
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Q3Mesh"
	mesh_instance.owner = root_node

	var array_mesh = ArrayMesh.new()

	# We might have multiple materials. We can create a dictionary from texture index to SurfaceTool.
	var surface_tools = {}

	# Iterate over each face and convert it into triangles
	# Face fields used:
	#   "type" (1=polygon, 3=mesh)
	#   "first_vertex": base vertex index in 'vertices' array
	#   "num_vertices": number of vertices for the face (for reference)
	#   "first_meshvert": start index in meshverts array
	#   "num_meshverts": number of meshverts (indices)
	#   "texture": index of the shader/texture
	#   vertices array elements have keys: "position", "normal", "uv", "color"
	# 
	# The actual vertex index for each meshvert m is: face.first_vertex + meshverts[face.first_meshvert + m]

	for face in faces:
		var ftype = face["type"]
		if ftype != 1 and ftype != 3:
			# Skip patch (2) and billboard (4) for this example
			continue

		var tex_index = face["texture"] # texture/shader index for this face
		var st: SurfaceTool
		
		if surface_tools.has(tex_index):
			st = surface_tools[tex_index]
		else:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Load or assign a material for this texture index if you have texture/material info:
			var mat = load_q3_material_for_texture(textures[tex_index]["name"]) # Implement this function as needed.
			st.set_material(mat)
			surface_tools[tex_index] = st

		var first_vertex = face["first_vertex"]
		var num_meshverts = face["num_meshverts"]
		var first_meshvert = face["first_meshvert"]

		# Extract all vertex indices for this face
		var indices = []
		for i in range(num_meshverts):
			var vert_offset = meshverts[first_meshvert + i]
			var vert_index = first_vertex + vert_offset
			indices.append(vert_index)

		# Q3 polygon faces are usually fans or strips. 
		# The simplest approach is to fan triangulate assuming the face is a fan:
		# (0, i+1, i+2) forms a triangle for i in range(num_meshverts-2)
		# This works for many Q3 polygon faces (they are often fans).
		# For mesh (type 3), these are often triangle fans/strips as well.
		# If you need more complex handling, refer to Q3 BSP docs.

		for i in range(num_meshverts - 2):
			var idx0 = indices[0]
			var idx1 = indices[i + 1]
			var idx2 = indices[i + 2]

			var v0 = vertices[idx0]
			var v1 = vertices[idx1]
			var v2 = vertices[idx2]

			# Positions, normals already converted to Godot space in read_q3_vertices
			var p0 = v0["position"] * unit_scale
			var p1 = v1["position"] * unit_scale
			var p2 = v2["position"] * unit_scale

			var uv0 = v0["uv"]
			var uv1 = v1["uv"]
			var uv2 = v2["uv"]

			var n0 = v0["normal"]
			var n1 = v1["normal"]
			var n2 = v2["normal"]

			var c0 = v0["color"]
			var c1 = v1["color"]
			var c2 = v2["color"]

			# Add these vertices to the SurfaceTool in clockwise or counterclockwise order
			# Ensure correct winding (if not correct, swap idx1 and idx2)
			st.set_normal(n0)
			st.set_uv(uv0)
			st.set_color(c0)
			st.add_vertex(p0)

			st.set_normal(n1)
			st.set_uv(uv1)
			st.set_color(c1)
			st.add_vertex(p1)

			st.set_normal(n2)
			st.set_uv(uv2)
			st.set_color(c2)
			st.add_vertex(p2)

	# Commit all surfaces
	# Each texture index got its own SurfaceTool, so each texture is its own surface.
	for tex_index in surface_tools.keys():
		var st = surface_tools[tex_index]
		st.generate_tangents() # optional
		array_mesh = st.commit(array_mesh)

	mesh_instance.mesh = array_mesh
	return mesh_instance

func load_q3_material_for_texture(name : StringName) -> Material:
	var width := 0
	var height := 0
	var material : Material = null

	var material_path : String
	if (texture_material_rename.has(name)):
		material_path = texture_material_rename[name]
	else:
		material_path = material_path_pattern.replace("{texture_name}", name)

	var image_path : String
	var texture : Texture2D = null
	var texture_emission : Texture2D = null

	if (texture_path_remap.has(name)):
		image_path = texture_path_remap[name]
	else:
		image_path = texture_path_pattern.replace("{texture_name}", name)

	var original_image_path := image_path
	if (!ResourceLoader.exists(image_path)):
		image_path = str(image_path.get_basename(), ".jpg") # Jpeg fallback
	if (ResourceLoader.exists(image_path)):
		texture = load(image_path)
		if (texture):
			width = texture.get_width()
			height = texture.get_height()
			print(name, ": External image width: ", width, " height: ", height)
	else:
		print("Could not load ", original_image_path)

	var image_emission_path : String
	image_emission_path = texture_emission_path_pattern.replace("{texture_name}", name)
	if (ResourceLoader.exists(image_emission_path)):
		texture_emission = load(image_emission_path)

	if (ResourceLoader.exists(material_path)):
		material = load(material_path)

	if (material && !overwrite_existing_materials):
		# Try to get the width/height from the existing material if needed
		if ((width == 0 || height == 0) && material is BaseMaterial3D):
			print("Attempting to get image size from base material for ", name)
			texture = material.albedo_texture
			if (texture):
				width = texture.get_width()
				height = texture.get_height()
				print("Material texture width: ", width, " height: ", height)
		elif (material && material is ShaderMaterial):
			var parameters_to_check : PackedStringArray = [ "albedo_texture", "texture_albedo", "texture", "albedo", "texture_diffuse" ]
			for param_name in parameters_to_check:
				var test = material.get_shader_parameter(param_name)
				if (test is Texture2D):
					print("Got ", param_name, " from ShaderMaterial for ", name)
					texture = test
					if (width == 0 || height == 0):
						width = texture.get_width()
						height = texture.get_height()
					break
	else:
		# Need to create a new material
		print(name, ": Need to create a new material.")
		if (texture && generate_texture_materials):
			print("Creating material with texture for ", name)
			material = StandardMaterial3D.new()
			material.albedo_texture = texture
			if (texture_emission):
				material.emission_enabled = true
				material.emission_texture = texture_emission
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
			material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

			if (save_separate_materials):
				print("Save separate materials.")
				# Optionally, if you need to write the texture or material to disk:
				# In Q3, textures are usually external, so you don't need to create or write them out.
				# Just skip if you don't need to do that.

				var material_dir := material_path.get_base_dir()
				print("Material dir: ", material_dir)
				if (!DirAccess.dir_exists_absolute(material_dir)):
					DirAccess.make_dir_recursive_absolute(material_dir)
				var err := ResourceSaver.save(material, material_path)
				if (err == OK):
					print("Wrote material: ", material_path)
					material.take_over_path(material_path)
				else:
					printerr("Failed to write to ", material_path)
		else:
			# No texture found, assign a fallback color
			print("No texture found for ", name, ". Assigning random color.")
			material = StandardMaterial3D.new()
			material.albedo_color = Color(randf_range(0.0, 1.0), randf_range(0.0, 1.0), randf_range(0.0, 1.0))

	return material
