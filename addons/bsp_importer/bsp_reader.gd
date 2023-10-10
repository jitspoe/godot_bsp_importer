extends Node

class_name BSPReader

const USE_TRIANGLE_COLLISION := false # To use convex collision, engine needs to support compute_convex_mesh_points
# Documentation: https://docs.godotengine.org/en/latest/tutorials/plugins/editor/import_plugins.html


const CONTENTS_EMPTY := -1
const CONTENTS_SOLID := -2
const CONTENTS_WATER := -3
#define CONTENTS_SLIME        -4
#define CONTENTS_LAVA         -5
#define CONTENTS_SKY          -6
#define CONTENTS_ORIGIN       -7
#define CONTENTS_CLIP         -8
#define CONTENTS_CURRENT_0    -9
#define CONTENTS_CURRENT_90   -10
#define CONTENTS_CURRENT_180  -11
#define CONTENTS_CURRENT_270  -12
#define CONTENTS_CURRENT_UP   -13
#define CONTENTS_CURRENT_DOWN -14
#define CONTENTS_TRANSLUCENT  -15


const CLIPNODES_STRUCT_SIZE := (4 + 2 + 2) # 32bit int for plane index, 2 16bit children.
const NODES_STRUCT_SIZE_Q1BSP := (4 + 2 + 2 + 2 * 6 + 2 + 2) # 32bit int for plane index, 2 16bit children.  bbox short, face id, face num
const NODES_STRUCT_SIZE_Q1BSP2 := (4 + 4 + 4 + 4 * 6 + 4 + 4) # 32bit int for plane index, 2 32bit children.  bbox int32?, face id, face num

#typedef struct
#{ long type;                   // Special type of leaf
#  long vislist;                // Beginning of visibility lists
#                               //     must be -1 or in [0,numvislist[
#  bboxshort_t bound;           // Bounding box of the leaf
#  u_short lface_id;            // First item of the list of faces
#                               //     must be in [0,numlfaces[
#  u_short lface_num;           // Number of faces in the leaf  
#  u_char sndwater;             // level of the four ambient sounds:
#  u_char sndsky;               //   0    is no sound
#  u_char sndslime;             //   0xFF is maximum volume
#  u_char sndlava;              //
#} dleaf_t;

const LEAF_SIZE_Q1BSP := 4 + 4 + 2 * 6 + 2 + 2 + 1 + 1 + 1 + 1
const LEAF_SIZE_BSP2 := 4 + 4 + 4 * 6 + 4 + 4 + 1 + 1 + 1 + 1


class BSPEdge:
	var vertex_index_0 : int
	var vertex_index_1 : int
	func read_edge_16_bit(file : FileAccess) -> int:
		vertex_index_0 = file.get_16()
		vertex_index_1 = file.get_16()
		return 4 # 2 2 byte values
	func read_edge_32_bit(file : FileAccess) -> int:
		vertex_index_0 = file.get_32()
		vertex_index_1 = file.get_32()
		return 8 # 2 4 byte values


class BSPModelData:
	var bound_min : Vector3
	var bound_max : Vector3
	var origin : Vector3
	var node_id0 : int
	var node_id1 : int
	var node_id2 : int
	var node_id3 : int
	var num_leafs : int # For vis?
	var face_index : int
	var face_count : int

const MODEL_DATA_SIZE_Q1_BSP := 2 * 3 * 4 + 3 * 4 + 7 * 4

func read_model_data_q1_bsp(model_data : BSPModelData):
	# Since some axes are negated here, min/max is funky.
	var mins := read_vector_convert_scaled()
	var maxs := read_vector_convert_scaled()
	model_data.bound_min = Vector3(min(mins.x, maxs.x), min(mins.y, maxs.y), min(mins.z, maxs.z))
	model_data.bound_max = Vector3(max(mins.x, maxs.x), max(mins.y, maxs.y), max(mins.z, maxs.z))
	model_data.origin = read_vector_convert_scaled()
	model_data.node_id0 = file.get_32()
	model_data.node_id1 = file.get_32()
	model_data.node_id2 = file.get_32()
	model_data.node_id3 = file.get_32()
	model_data.num_leafs = file.get_32()
	model_data.face_index = file.get_32()
	model_data.face_count = file.get_32()


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


class BSPTexture:
	var name : String
	var width : int
	var height : int
	var material : Material
	var is_water := false
	var is_transparent := false
	static func get_data_size() -> int:
		return 40 # 16 + 4 * 6
	func read_texture(file : FileAccess, material_path_pattern : String, texture_material_rename : Dictionary) -> int:
		name = file.get_buffer(16).get_string_from_ascii()
		if name[0] == '*':
			name = name.substr(1)
			is_water = true
			is_transparent = true
		width = file.get_32()
		height = file.get_32()
		print("texture: ", name, " width: ", width, " height: ", height)
		#material = load("res://materials/%s_material.tres" % name)
		var material_path : String
		if (texture_material_rename.has(name)):
			material_path = texture_material_rename[name]
		else:
			material_path = material_path_pattern.replace("{texture_name}", name)
		if (name != "skip"):
			if (width != 0 && height != 0): # Temp hack for nonexistent textures.
				material = load(material_path)
			if (!material):
				material = StandardMaterial3D.new()
				material.albedo_color = Color(randf_range(0.0, 1.0), randf_range(0.0, 1.0), randf_range(0.0, 1.0))
		file.get_32() # for mip levels
		file.get_32() # for mip levels
		file.get_32() # for mip levels
		file.get_32() # for mip levels
		return get_data_size()


class BSPTextureInfo:
	var vec_s : Vector3
	var offset_s : float
	var vec_t : Vector3
	var offset_t : float
	var texture_index : int
	var flags : int
	static func get_data_size() -> int:
		return 40 # 3 * 2 * 4 + 4 * 2 + 2 * 4
	func read_texture_info(file : FileAccess) -> int:
		#vec_s = BSPImporterPlugin.convert_normal_vector_from_quake(Vector3(file.get_float(), file.get_float(), file.get_float()))
		vec_s = BSPReader.read_vector_convert_unscaled(file)
		offset_s = file.get_float()
		#vec_t = BSPImporterPlugin.convert_normal_vector_from_quake(Vector3(file.get_float(), file.get_float(), file.get_float()))
		vec_t = BSPReader.read_vector_convert_unscaled(file)
		offset_t = file.get_float()
		texture_index = file.get_32()
		#print("texture_index: ", texture_index)
		flags = file.get_32()
		return get_data_size()


class BSPFace:
	var plane_id : int
	var side : bool
	var edge_list_id : int
	var num_edges : int
	var texinfo_id : int
	var light_type : int
	var light_base : int
	var light_model_0 : int
	var light_model_1 : int
	var lightmap : int
	static func get_data_size_q1bsp() -> int:
		return 20
	static func get_data_size_bsp2() -> int: # for bsp2
		return 20 + 2 * 4 # plane id, side, num edges all have an extra 2 bytes going from 16 to 32 bit
	func print_face():
		print("BSPFace: plane_id: ", plane_id, " side: ", side, " edge_list_id: ", edge_list_id, " num_edges: ", num_edges, " texinfo_id: ", texinfo_id)
	func read_face_q1bsp(file : FileAccess) -> int:
		plane_id = file.get_16()
		side = file.get_16() > 0
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
		#print("plane_id ", plane_id)
		side = file.get_32()
		#print("side ", side)
		edge_list_id = file.get_32()
		#print("edge_list_id ", edge_list_id)
		num_edges = file.get_32()
		#print("num_edges ", num_edges)
		texinfo_id = file.get_32()
		#print("texinfo_id ", texinfo_id)
		light_type = file.get_8()
		light_base = file.get_8()
		light_model_0 = file.get_8()
		light_model_1 = file.get_8()
		lightmap = file.get_32()
		#print("lightmap ", lightmap)
		return get_data_size_bsp2()


const MAX_15B := 1 << 15
const MAX_16B := 1 << 16

static func unsigned16_to_signed(unsigned : int) -> int:
	return (unsigned + MAX_15B) % MAX_16B - MAX_15B

const MAX_31B = 1 << 31
const MAX_32B = 1 << 32

static func unsigned32_to_signed(unsigned : int) -> int:
	return (unsigned + MAX_31B) % MAX_32B - MAX_31B


# Converts Z up to Y up
#static func convert_vector_from_quake_unscaled(quake_vector : Vector3) -> Vector3:
#	return Vector3(quake_vector.x, quake_vector.z, -quake_vector.y)


#static func convert_vector_from_quake_scaled(quake_vector : Vector3) -> Vector3:
#	return Vector3(quake_vector.x, quake_vector.z, -quake_vector.y) * UNIT_SCALE


# X is forward in Quake, -Z is forward in Godot.  Z is up in Quake, Y is up in Godot
static func convert_vector_from_quake_unscaled(quake_vector : Vector3) -> Vector3:
	return Vector3(-quake_vector.y, quake_vector.z, -quake_vector.x)


static func convert_vector_from_quake_scaled(quake_vector : Vector3, scale: float) -> Vector3:
	return Vector3(-quake_vector.y, quake_vector.z, -quake_vector.x) * scale


static func read_vector_convert_unscaled(file : FileAccess) -> Vector3:
	return convert_vector_from_quake_unscaled(Vector3(file.get_float(), file.get_float(), file.get_float()))


func read_vector_convert_scaled() -> Vector3:
	return convert_vector_from_quake_scaled(Vector3(file.get_float(), file.get_float(), file.get_float()), _unit_scale)


var error := ERR_UNCONFIGURED
var material_path_pattern : String
var water_template_path : String
var texture_material_rename : Dictionary
var entity_remap : Dictionary
var array_of_planes_array := []
var array_of_planes : PackedInt32Array = []
var water_planes_array := []  # Array of arrays of planes
var file : FileAccess
var leaves_offset : int
var nodes_offset : int
var root_node : Node3D
var plane_normals : PackedVector3Array
var plane_distances : PackedFloat32Array
var model_scenes : Dictionary = {}
var is_bsp2 := false
var _unit_scale: float = 1.0

var inverse_scale_fac: float = 32.0:
	set(v):
		inverse_scale_fac = v
		_unit_scale = 1.0 / v


func clear_data():
	error = ERR_UNCONFIGURED
	array_of_planes_array = []
	array_of_planes = []
	water_planes_array = []  # Array of arrays of planes
	if (file):
		file.close()
		file = null
	root_node = null
	plane_normals = []
	plane_distances = []
	model_scenes = {}


func read_bsp(source_file : String) -> Node:
	clear_data() # Probably not necessary, but just in case somebody reads a bsp file with the same instance
	print("Attempting to import %s" % source_file)
	print("Material path pattern: ", material_path_pattern)
	file = FileAccess.open(source_file, FileAccess.READ)

	if (!file):
		error = FileAccess.get_open_error()
		print("Failed to open %s: %d" % [source_file, error])
		return null

	root_node = Node3D.new()
	root_node.name = source_file.get_file().get_basename() # Get the file out of the path and remove file extension

	# Read the header
	var is_q2 := false
	is_bsp2 = false
	var has_textures := true
	var has_clipnodes := true
	var has_brush_table := false
	var bsp_version := file.get_32()
	var index_bits_32 := false
	print("BSP version: %d\n" % bsp_version)
	if (bsp_version == 1347633737): # "IBSP" - Quake 2 BSP format
		print("IBSP (Quake2?) format - not supported, yet.")
		is_q2 = true
		has_textures = false
		has_clipnodes = false
		has_brush_table = true
		bsp_version = file.get_32()
		print("BSP sub-version: %d\n" % bsp_version)
		
		file.close()
		file = null
		return
	if (bsp_version == 1112756274): # "2PSB" - depricated extended quake BSP format.
		print("2PSB format not supported.")
		file.close()
		file = null
		return
	if (bsp_version == 844124994): # "BSP2" - extended Quake BSP format
		print("BSP2 extended Quake format.")
		is_bsp2 = true
		index_bits_32 = true
	var entity_offset := file.get_32()
	var entity_size := file.get_32()
	var planes_offset := file.get_32()
	var planes_size := file.get_32()
	var textures_offset := file.get_32() if has_textures else 0
	var textures_size := file.get_32() if has_textures else 0
	var verts_offset := file.get_32()
	var verts_size := file.get_32()
	var vis_offset := file.get_32()
	var vis_size := file.get_32()
	nodes_offset = file.get_32()
	var nodes_size := file.get_32()
	var texinfo_offset := file.get_32()
	var texinfo_size := file.get_32()
	var faces_offset := file.get_32()
	var faces_size := file.get_32()
	var lightmaps_offset := file.get_32()
	var lightmaps_size := file.get_32()
	var clipnodes_offset := file.get_32() if has_clipnodes else 0
	var clipnodes_size := file.get_32() if has_clipnodes else 0
	leaves_offset = file.get_32()
	var leaves_size := file.get_32()
	var listfaces_size := file.get_32()
	var listfaces_offset := file.get_32()
	var leaf_brush_table_offset := file.get_32() if has_brush_table else 0
	var leaf_brush_table_size := file.get_32() if has_brush_table else 0
	var edges_offset := file.get_32()
	var edges_size := file.get_32()
	var listedges_offset := file.get_32()
	var listedges_size := file.get_32()
	var models_offset := file.get_32()
	var models_size := file.get_32()
	# Q2-specific
	var brushes_offset := file.get_32() if has_brush_table else 0
	var brushes_size := file.get_32() if has_brush_table else 0
	var brush_sides_offset := file.get_32() if has_brush_table else 0
	var brush_sides_size := file.get_32() if has_brush_table else 0
	# Pop
	# Areas
	# Area portals
	
	# Read vertex data
	var verts : PackedVector3Array
	file.seek(verts_offset)
	var vert_data_left := verts_size
	var vertex_count := verts_size / (4 * 3)
	verts.resize(vertex_count)
	for i in vertex_count:
		verts[i] = convert_vector_from_quake_scaled(Vector3(file.get_float(), file.get_float(), file.get_float()), _unit_scale)
		#print("Vert: ", verts[i])

	# Read entity data
	file.seek(entity_offset)
	var entity_string : String = file.get_buffer(entity_size).get_string_from_ascii()
	print("Entity data: ", entity_string)
	var entity_dict_array := parse_entity_string(entity_string)
	convert_entity_dict_to_scene(entity_dict_array)
	

	#print("edges_offset: ", edges_offset)
	file.seek(edges_offset)
	var edges_data_left := edges_size
	var edges := []
	while (edges_data_left > 0):
		var edge := BSPEdge.new()
		if (index_bits_32):
			edges_data_left -= edge.read_edge_32_bit(file)
		else:
			edges_data_left -= edge.read_edge_16_bit(file)
		#print("edge v 0: ", edge.vertex_index_0)
		#print("edge v 1: ", edge.vertex_index_0)
		edges.append(edge)
	#print("edges_data_left: ", edges_data_left)

	var edge_list : PackedInt32Array
	var num_edge_list := listedges_size / 4
	edge_list.resize(num_edge_list)
	file.seek(listedges_offset)
	for i in num_edge_list:
		#edge_list[i] = unsigned16_to_signed(file.get_16())
		# Page was wrong, this is 32bit
		edge_list[i] = file.get_32()
		#print("edge list: ", edge_list[i])

	var num_planes := planes_size / (4 * 5) # vector, float, and int32
	plane_normals.resize(num_planes)
	plane_distances.resize(num_planes)
	file.seek(planes_offset)
	for i in num_planes:
		var quake_plane_normal := Vector3(file.get_float(), file.get_float(), file.get_float())
		plane_normals[i] = convert_vector_from_quake_unscaled(quake_plane_normal)
		plane_distances[i] = file.get_float() * _unit_scale
		var _type = file.get_32() # 0 = X-Axial plane, 1 = Y-axial pane, 2 = z-axial plane, 3 nonaxial, toward x, 4 y, 5 z
		#print("Quake plane ", i, ": ", quake_plane_normal, " dist: ", plane_distances[i], " type: ", _type)
	#print("plane_normals: ", plane_normals)
	file.seek(clipnodes_offset)
	var num_clipnodes := clipnodes_size / CLIPNODES_STRUCT_SIZE
	print("clipnodes offset: ", clipnodes_offset, " clipnodes_size: ", clipnodes_size, " num_clipnodes: ", num_clipnodes)
	# todo
	
	# Read in the textures (to get the sizes for UV's)
	print("textures offset: ", textures_offset)
	#var texture_data_left := textures_size
	#var num_textures := textures_size / BSPTexture.get_data_size()
	var textures := []
	var texture_offset_offsets : PackedInt32Array # Offset to texture area has an array of offsets relative to the start of this
	
	file.seek(textures_offset)
	var num_textures := file.get_32()
	texture_offset_offsets.resize(num_textures)
	print("num_textures: ", num_textures)
	textures.resize(num_textures)
	for i in num_textures:
		texture_offset_offsets[i] = file.get_32()
		#print("offset offset: ", texture_offset_offsets[i])
	for i in num_textures:
		var texture_offset := texture_offset_offsets[i]
		if (texture_offset < 0):
			print("Missing texture ", i, " make sure wad file is compiled into map.")
			var bad_tex := BSPTexture.new()
			bad_tex.width = 64
			bad_tex.height = 64
			bad_tex.name = "_bad_texture_"
			textures[i] = bad_tex
		else:
			var complete_offset := textures_offset + texture_offset
			file.seek(complete_offset)
			textures[i] = BSPTexture.new()
			textures[i].read_texture(file, material_path_pattern, texture_material_rename)
		#print("texture: ", textures[i].name, " ", textures[i].width, "x", textures[i].height)

	# UV stuff
	file.seek(texinfo_offset)
	var num_texinfo := texinfo_size / BSPTextureInfo.get_data_size()
	var textureinfos := []
	textureinfos.resize(num_texinfo)
	for i in num_texinfo:
		textureinfos[i] = BSPTextureInfo.new()
		textureinfos[i].read_texture_info(file)
		#print("Textureinfo: ", textureinfos[i].vec_s, " ", textureinfos[i].offset_s, " ", textureinfos[i].vec_t, " ", textureinfos[i].offset_t, " ", textureinfos[i].texture_index)

	# Get model data:
	var model_data_size := MODEL_DATA_SIZE_Q1_BSP if !is_q2 else BSPModelDataQ2.get_data_size()
	var num_models := models_size / model_data_size
	var model_data := []
	model_data.resize(num_models)
	for i in num_models:
		if (is_q2):
			model_data[i] = BSPModelDataQ2.new()
			file.seek(models_offset + model_data_size * i) # We'll skip around in the file loading data
			model_data[i].read_model(file)
		else:
			model_data[i] = BSPModelData.new()
			file.seek(models_offset + model_data_size * i) # We'll skip around in the file loading data
			read_model_data_q1_bsp(model_data[i])

	file.seek(faces_offset)
	var face_data_left := faces_size
	var bsp_face := BSPFace.new()
	var begun := false
	var previous_tex_name := "UNSET"

	for model_index in num_models:
		var surface_tools := {}
		water_planes_array = [] # Clear that out so water isn't duplicated for each mesh. :D
		var needs_import := false
		var parent_node : Node3D
		var parent_inv_transform := Transform3D() # If a world model is rotated (such as a trigger) we want to keep things in the correct spot
		if (model_index == 0): # worldspawn
			needs_import = true # Always import worldspawn.
			var static_body := StaticBody3D.new()
			static_body.name = "StaticBody"
			root_node.add_child(static_body, true)
			static_body.owner = root_node
			parent_node = static_body
		if (model_scenes.has(model_index)):
			needs_import = true # Import supported entities.
			parent_node = model_scenes[model_index]
			parent_inv_transform = parent_node.transform.inverse()
		if (needs_import): # Only import the worldspawn for now, since doors and triggers will just block movement
			var bsp_model : BSPModelData = model_data[model_index]
			var face_size := BSPFace.get_data_size_q1bsp() if !is_bsp2 else BSPFace.get_data_size_bsp2()
			file.seek(faces_offset + bsp_model.face_index * face_size)
			var num_faces := bsp_model.face_count
			print("num_faces: ", num_faces)
			for face_index in num_faces:
				if (is_bsp2):
					bsp_face.read_face_bsp2(file)
				else:
					bsp_face.read_face_q1bsp(file)
				if (bsp_face.texinfo_id > textureinfos.size()):
					print("Bad texinfo_id: ", bsp_face.texinfo_id)
					bsp_face.print_face()
					continue
				# Get the texture from the face
				var tex_info : BSPTextureInfo = textureinfos[bsp_face.texinfo_id]
				var texture : BSPTexture = textures[tex_info.texture_index]
				var surf_tool : SurfaceTool
				if (texture.is_transparent):
					# Transparent meshes need to be sorted, so make each face its own mesh for now.
					surf_tool = SurfaceTool.new()
					surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					surf_tool.set_material(texture.material)
				else:
					if (surface_tools.has(texture.name)):
						surf_tool = surface_tools[texture.name]
					else:
						surf_tool = SurfaceTool.new()
						surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
						surf_tool.set_material(texture.material)
						surface_tools[texture.name] = surf_tool
				
				#print("plane id: ", bsp_face.plane_id)
				#print("face edge count: ", bsp_face.num_edges)
				if (bsp_face.num_edges < 3):
					print("face with fewer than 3 edges.")
					bsp_face.print_face() # TODO: Debug, testing
					continue
				var edge_list_index_start := bsp_face.edge_list_id
				#print("edge list index start: ", edge_list_index_start)
				var i := 0
				var face_verts : PackedVector3Array
				face_verts.resize(bsp_face.num_edges)
				var face_normals : PackedVector3Array
				face_normals.resize(bsp_face.num_edges)
				var face_normal := Vector3.UP
				if (bsp_face.plane_id < plane_normals.size()):
					face_normal = plane_normals[bsp_face.plane_id]
				else:
					print("Plane id out of bounds: ", bsp_face.plane_id)
				if (bsp_face.side):
					face_normal = -face_normal
				
				var vs := tex_info.vec_s
				var vt := tex_info.vec_t
				var s := tex_info.offset_s
				var t := tex_info.offset_t
				#print("texture_index: ", tex_info.texture_index)
				
				var tex_width : int = texture.width
				var tex_height : int = texture.height
				var tex_name : String = texture.name
				if (previous_tex_name != tex_name):
					previous_tex_name = tex_name
				#print("width: ", tex_width, " height: ", tex_height)
				var face_uvs : PackedVector2Array
				face_uvs.resize(bsp_face.num_edges)
				var tex_scale_x := 1.0 / (_unit_scale * tex_width)
				var tex_scale_y := 1.0 / (_unit_scale * tex_height)
				#print("normal: ", face_normal)
				for edge_list_index in range(edge_list_index_start, edge_list_index_start + bsp_face.num_edges):
					var vert_index_0 : int
					var reverse_order := false
					var edge_index := edge_list[edge_list_index]
					if (edge_index < 0):
						reverse_order = true
						edge_index = -edge_index
					
					if (reverse_order): # Not sure which way this should be flipped to get correct tangents
						vert_index_0 = edges[edge_index].vertex_index_1
					else:
						vert_index_0 = edges[edge_index].vertex_index_0
					var vert := verts[vert_index_0]
					#print("vert (%s): %d, " % ["r" if reverse_order else "f", vert_index_0], vert)
					face_verts[i] = vert
					face_normals[i] = face_normal
					face_uvs[i].x = vert.dot(vs) * tex_scale_x + s / tex_width
					face_uvs[i].y = vert.dot(vt) * tex_scale_y + t / tex_height
					#print("vert: ", vert, " vs: ", vs, " d: ", vert.dot(vs), " vt: ", vt, " d: ", vert.dot(vt))
					i += 1
				surf_tool.add_triangle_fan(face_verts, face_uvs, [], [], face_normals)
				
				if (texture.is_transparent): # Need to create unique meshes for each transparent surface so they sort properly.
					var mesh_instance := MeshInstance3D.new()
			
					# Create a mesh out of all the surfaces
					surf_tool.generate_tangents()
					var array_mesh : ArrayMesh = null
					array_mesh = surf_tool.commit(array_mesh)
					mesh_instance.mesh = array_mesh
					mesh_instance.name = "TransparentMesh"
					parent_node.add_child(mesh_instance, true)
					mesh_instance.transform = parent_inv_transform
					mesh_instance.owner = root_node
	
			# Put all non-transparent textures into a single mesh
			var mesh_instance := MeshInstance3D.new()
			
			# Create a mesh out of all the surfaces
			var array_mesh : ArrayMesh = null
			for texture_name in surface_tools:
				var surf_tool : SurfaceTool = surface_tools[texture_name]
				#print("surf_tool: ", surf_tool, " tex name: ", texture_name)
				surf_tool.generate_tangents()
				array_mesh = surf_tool.commit(array_mesh)
			mesh_instance.mesh = array_mesh
			mesh_instance.name = "Mesh"
			parent_node.add_child(mesh_instance, true)
			mesh_instance.transform = parent_inv_transform
			mesh_instance.owner = root_node
			#print("face_data_left: ", face_data_left)

			# Collision.
			# Could ultimately read the clip stuff and create convex shapes, but just going to use triangle mesh collision for now.
			if (USE_TRIANGLE_COLLISION):
				var collision_shape := CollisionShape3D.new()
				collision_shape.name = "CollisionShape"
				collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
				parent_node.add_child(collision_shape, true)
				mesh_instance.transform = parent_inv_transform
				collision_shape.owner = root_node
				# Apparently we have to let the gc handle this autamically now: file.close()
			else: # Attempt to create collision out of BSP nodes
				# Clear these out, as we may be importing multiple models.
				array_of_planes_array = []
				array_of_planes = []
				if (0): # Clipnodes -- these are lossy and account for player size
					print("Node 0: ", bsp_model.node_id0, " Node 1: ", bsp_model.node_id1, " Node 2: ", bsp_model.node_id2, " Node 3: ", bsp_model.node_id3)
					file.seek(clipnodes_offset + bsp_model.node_id0 * CLIPNODES_STRUCT_SIZE) # Not sure which node I should be using here.  I think 0 is for rendering and 1 is point collision.
					#test_print_planes(file, planes_offset)
					read_clipnodes_recursive(file, clipnodes_offset)
				else:
					var seek_location := nodes_offset + bsp_model.node_id0 * (NODES_STRUCT_SIZE_Q1BSP if !is_bsp2 else NODES_STRUCT_SIZE_Q1BSP2)
					#print("Reading nodes: ", nodes_offset, " ", bsp_model.node_id0, " location: ", seek_location)
					file.seek(seek_location)
					read_nodes_recursive()
				#print("Array of planes array: ", array_of_planes_array)
				var model_mins := bsp_model.bound_min;
				var model_maxs := bsp_model.bound_max;
				print("Model mins: ", model_mins, " Model maxs: ", model_maxs)
				print("Origin: ", bsp_model.origin)
				var model_mins_maxs_planes : Array[Plane]
				model_mins_maxs_planes.push_back(Plane(Vector3.RIGHT, model_maxs.x))
				model_mins_maxs_planes.push_back(Plane(Vector3.UP, model_maxs.y))
				model_mins_maxs_planes.push_back(Plane(Vector3.BACK, model_maxs.z))
				model_mins_maxs_planes.push_back(Plane(Vector3.LEFT, -model_mins.x))
				model_mins_maxs_planes.push_back(Plane(Vector3.DOWN, -model_mins.y))
				model_mins_maxs_planes.push_back(Plane(Vector3.FORWARD, -model_mins.z))

				# Create collision shapes for world
				create_collision_shapes(parent_node, array_of_planes_array, model_mins_maxs_planes, parent_inv_transform)

				# Create collision shapes for water, if we have any
				if (water_planes_array.size() > 0):
					var water_body : Node = load(water_template_path).instantiate()
					parent_node.add_child(water_body, true)
					water_body.transform = parent_inv_transform
					water_body.owner = root_node
					create_collision_shapes(water_body, water_planes_array, model_mins_maxs_planes, Transform3D())
	file.close()
	file = null
	return root_node


func parse_entity_string(entity_string : String) -> Array:
	var ent_dict := {}
	var ent_dict_array := []
	var in_key_string := false
	var in_value_string := false
	var key : String
	var value : String
	var parsed_key := false
	for char in entity_string:
		if (in_key_string):
			if (char == '"'):
				in_key_string = false
				parsed_key = true
			else:
				key += char
		elif (in_value_string):
			if (char == '"'):
				in_value_string = false
				ent_dict[key] = value
				key = ""
				value = ""
				parsed_key = false
			else:
				value += char
		elif (char == '"'):
			if (parsed_key):
				in_value_string = true
			else:
				in_key_string = true
		elif (char == '}'):
			ent_dict_array.push_back(ent_dict)
		elif (char == '{'):
			ent_dict = {}
			parsed_key = false
	print("ent dict: ", ent_dict_array)
	return ent_dict_array


func convert_entity_dict_to_scene(ent_dict_array : Array):
	for ent_dict in ent_dict_array:
		if (ent_dict.has("classname")):
			var classname : String = ent_dict["classname"]
			print("Classname: ", classname)
			if (entity_remap.has(classname)):
				var scene_path : String = entity_remap[classname]
				print("Remapping ", classname, " to ", scene_path)
				var scene_resource = load(scene_path)
				if (!scene_resource):
					print("Failed to load ", scene_path)
				else:
					var scene : Node = scene_resource.instantiate()
					if (!scene):
						print("Failed to instantiate scene: ", scene_path)
					else:
						var origin := Vector3.ZERO
						if (ent_dict.has("origin")):
							var origin_string : String = ent_dict["origin"]
							origin = string_to_origin(origin_string, _unit_scale)
						var mangle_string : String = ent_dict.get("mangle", "")
						var angle_string : String = ent_dict.get("angle", "")
						var basis := Basis()
						if (angle_string.length() > 0):
							basis = angle_to_basis(angle_string)
						if (mangle_string.length() > 0):
							basis = mangle_to_basis(mangle_string)
						var transform := Transform3D(basis, origin)
						root_node.add_child(scene, true)
						scene.transform = transform
						scene.owner = root_node
						if (ent_dict.has("model")):
							var model_value : String = ent_dict["model"]
							# Models that start with a * are contained with in the BSP file (ex: doors, triggers, etc)
							if (model_value[0] == '*'):
								model_scenes[model_value.substr(1).to_int()] = scene
						# For every key/value pair in the entity, see if there's a corresponding
						# variable in the gdscript and set it.
						for key in ent_dict:
							var string_value : String = ent_dict[key]
							var value = string_value
							if (key == "spawnflags"):
								value = value.to_int()

							# Allow scenes to have custom implementations of this so they can remap values or whatever
							# Returning true means it was handled.
							if (scene.has_method("set_import_value")):
								if (!scene.get_script().is_tool()):
									printerr(scene.name + " has 'set_import_value()' function but must have @tool set to work for imports.")
								else:
									if (scene.set_import_value(key, string_value)):
										continue

							var dest_value = scene.get(key) # Se if we can figure out the type of the destination value
							if (dest_value != null):
								var dest_type := typeof(dest_value)
								match (dest_type):
									TYPE_BOOL:
										value = string_value.to_int() != 0
									TYPE_INT:
										value = string_value.to_int()
									TYPE_FLOAT:
										value = string_value.to_float()
									TYPE_STRING:
										value = string_value
									TYPE_STRING_NAME:
										value = string_value
									TYPE_VECTOR3:
										value = string_to_vector3(string_value)
									_:
										printerr("Key value type not handled for ", key, " : ", dest_type)
										value = string_value # Try setting it to the string value and hope for the best.
							scene.set(key, value)
							
	print("model_scenes: ", model_scenes)


static func string_to_origin(origin_string : String, scale: float) -> Vector3:
	var vec := string_to_vector3(origin_string)
	return convert_vector_from_quake_scaled(vec, scale)


static func string_to_vector3(vec_string : String) -> Vector3:
	var vec := Vector3.ZERO
	var split := vec_string.split(" ")
	var i := 0
	for pos in split:
		if (i < 3):
			vec[i] = pos.to_float()
		i += 1
	return vec


static func mangle_to_basis(mangle_string : String) -> Basis:
	var split := mangle_string.split(" ")
	var angles := Vector3.ZERO
	var i := 0
	for pos in split:
		if (i < 3):
			angles[i] = deg_to_rad(pos.to_float())
		i += 1
	#var angles_ypr := Vector3(angles[1], angles[0], angles[2])
	#angles[1] -= PI * 0.5 # In Quake, X is forward (0 degrees).  In Godot, -Z is forward.
	angles[0] = - angles[0] # For some reason pitch is invertid in quake mangles
	var basis := Basis.from_euler(angles)
	return basis


static func angle_to_basis(angle_string : String) -> Basis:
	var angles := Vector3.ZERO
	angles[1] = deg_to_rad(angle_string.to_float())
	var basis := Basis.from_euler(angles)
	return basis


func create_collision_shapes(body : Node3D, planes_array, model_mins_maxs_planes, parent_inv_transform : Transform3D):
	print("Create collision shapes.")
	for i in planes_array.size():
		var plane_indexes : PackedInt32Array = planes_array[i]
		var convex_planes : Array[Plane]
		#print("Planes index: ", i)
		convex_planes.append_array(model_mins_maxs_planes)
		for plane_index in plane_indexes:
			# sign of 0 is 0, so we offset the index by 1.
			var plane := Plane(plane_normals[abs(plane_index) - 1] * sign(plane_index), (plane_distances[abs(plane_index) - 1]) * sign(plane_index))
			convex_planes.push_back(plane)
			#print("Plane ", plane_index, ": ", plane)
		var convex_points := convert_planes_to_points(convex_planes)
		if (convex_points.size() < 3):
			print("Convex shape creation failed ", i)
		else:
			var collision_shape := CollisionShape3D.new()
			#print("Convex planes: ", convex_planes)
			collision_shape.name = "Collision%d" % i
			collision_shape.shape = ConvexPolygonShape3D.new()
			collision_shape.shape.points = convex_points
			collision_shape.transform = parent_inv_transform
			#print("Convex points: ", convex_points)
			body.add_child(collision_shape, true)
			collision_shape.owner = root_node


func read_nodes_recursive():
	var plane_index := file.get_32()
	var child0 := unsigned16_to_signed(file.get_16()) if !is_bsp2 else unsigned32_to_signed(file.get_32())
	var child1 := unsigned16_to_signed(file.get_16()) if !is_bsp2 else unsigned32_to_signed(file.get_32())
	#print("plane: ", plane_index, " child0: ", child0, " child1: ", child1)
	# Hack upon hack -- store the plane index offset by 1, so we can negate the first index
	array_of_planes.push_back(-(plane_index + 1)) # Stupid nonsense where the front plane is negative.  Store the index as negative so we know to negate the plane later
	handle_node_child(child0)
	array_of_planes.resize(array_of_planes.size() - 1) # pop back
	array_of_planes.push_back(plane_index + 1)
	handle_node_child(child1)
	array_of_planes.resize(array_of_planes.size() - 1) # pop back


func handle_node_child(child_value : int):
	if (child_value < 0): # less than 0 means its a leaf.
		var leaf_id := ~child_value
		var file_offset := leaves_offset + leaf_id * (LEAF_SIZE_Q1BSP if !is_bsp2 else LEAF_SIZE_BSP2)
		#print("leaf_id: ", leaf_id, " file offset: ", file_offset)
		file.seek(file_offset)
		var leaf_type := unsigned32_to_signed(file.get_32())
		#print("leaf_type: ", leaf_type)
		if (leaf_type == CONTENTS_SOLID):
			array_of_planes_array.push_back(array_of_planes.duplicate())
		elif (leaf_type == CONTENTS_WATER):
			water_planes_array.push_back(array_of_planes.duplicate())
	else:
		file.seek(nodes_offset + child_value * (NODES_STRUCT_SIZE_Q1BSP if !is_bsp2 else NODES_STRUCT_SIZE_Q1BSP2))
		read_nodes_recursive()


func read_clipnodes_recursive(file : FileAccess, clipnodes_offset : int):
	var plane_index := file.get_32()
	var child0 := unsigned16_to_signed(file.get_16()) # Need to handle BSP2 if we ever use this
	var child1 := unsigned16_to_signed(file.get_16())
	print("plane: ", plane_index, " child0: ", child0, " child1: ", child1)
	array_of_planes.push_back(-plane_index) # Stupid nonsense where the front plane is negative.  Store the index as negative so we know to negate the plane later
	handle_clip_child(file, clipnodes_offset, child0)
	array_of_planes.resize(array_of_planes.size() - 1) # pop back
	array_of_planes.push_back(plane_index)
	handle_clip_child(file, clipnodes_offset, child1)
	array_of_planes.resize(array_of_planes.size() - 1) # pop back


func handle_clip_child(file : FileAccess, clipnodes_offset : int, child_value : int):
	if (child_value < 0): # less than 0 means its a leaf.
		if (child_value == CONTENTS_SOLID):
			array_of_planes_array.push_back(array_of_planes.duplicate())
	else:
		file.seek(clipnodes_offset + child_value * CLIPNODES_STRUCT_SIZE)
		read_clipnodes_recursive(file, clipnodes_offset)


func convert_planes_to_points(convex_planes : Array[Plane]) -> PackedVector3Array :
	# If you get errors about this, you're using a godot version that doesn't have this 
	# function exposed, yet.  Comment it out and uncomment the code below.
	#return Geometry3D.compute_convex_mesh_points(convex_planes)
	var clipper := BspClipper.new()
	clipper.begin()
	for plane in convex_planes:
		clipper.clip_plane(plane)
	clipper.filter_and_clean()
	
	return clipper.vertices
