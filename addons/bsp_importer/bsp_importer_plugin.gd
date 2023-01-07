@tool
extends EditorImportPlugin
class_name BSPImporterPlugin

const UNIT_SCALE := 1.0 / 32.0
# Documentation: https://docs.godotengine.org/en/latest/tutorials/plugins/editor/import_plugins.html


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
	#add_import_option("material_path_pattern", "res://materials/{texture_name}_material.tres")
	match preset_index:
		Presets.DEFAULT:
			return [{
				"name" : "material_path_pattern",
				"default_value" : "res://materials/{texture_name}_material.tres"
			},
			{
				"name" : "texture_material_rename",
				"default_value" : { "texture_name1" : "res://material/texture_name1_material.tres" }
			}]
		_:
			return []


func _get_option_visibility(_option, _options, _unknown_dictionary):
	return true



class BSPEdge:
	var vertex_index_0 : int
	var vertex_index_1 : int
	static func get_data_size() -> int:
		return 4 # 2 unsigned shorts
	func read_edge(file : FileAccess) -> int:
		vertex_index_0 = file.get_16()
		vertex_index_1 = file.get_16()
		return get_data_size()


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
	static func get_data_size() -> int:
		return 2 * 3 * 4 + 3 * 4 + 7 * 4
	func read_model(file : FileAccess):
		bound_min = Vector3(file.get_float(), file.get_float(), file.get_float())
		bound_max = Vector3(file.get_float(), file.get_float(), file.get_float())
		origin = Vector3(file.get_float(), file.get_float(), file.get_float())
		node_id0 = file.get_32()
		node_id1 = file.get_32()
		node_id2 = file.get_32()
		node_id3 = file.get_32()
		num_leafs = file.get_32()
		face_index = file.get_32()
		face_count = file.get_32()
		#print("origin: ", origin, "face_index: ", face_index, "face_count: ", face_count)


class BSPTexture:
	var name : String
	var width : int
	var height : int
	var material : Material
	static func get_data_size() -> int:
		return 40 # 16 + 4 * 6
	func read_texture(file : FileAccess, material_path_pattern : String, texture_material_rename : Dictionary) -> int:
		name = file.get_buffer(16).get_string_from_ascii()
		width = file.get_32()
		height = file.get_32()
		print("texture: ", name, " width: ", width, " height: ", height)
		#material = load("res://materials/%s_material.tres" % name)
		var material_path : String
		if (texture_material_rename.has(name)):
			material_path = texture_material_rename[name]
		else:
			material_path = material_path_pattern.replace("{texture_name}", name)
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
		vec_s = BSPImporterPlugin.read_vector_convert_unscaled(file)
		offset_s = file.get_float()
		#vec_t = BSPImporterPlugin.convert_normal_vector_from_quake(Vector3(file.get_float(), file.get_float(), file.get_float()))
		vec_t = BSPImporterPlugin.read_vector_convert_unscaled(file)
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
	static func get_data_size() -> int:
		return 20
	func read_face(file : FileAccess) -> int:
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
		return get_data_size()

const MAX_15B := 1 << 15
const MAX_16B := 1 << 16

func unsigned16_to_signed(unsigned : int) -> int:
	return (unsigned + MAX_15B) % MAX_16B - MAX_15B


static func convert_from_quake_units(quake_vector : Vector3) -> Vector3:
	return Vector3(-quake_vector.x, quake_vector.z, quake_vector.y) * UNIT_SCALE


static func convert_normal_vector_from_quake(quake_vector : Vector3) -> Vector3:
	return Vector3(-quake_vector.x, quake_vector.z, quake_vector.y)


static func read_vector_convert(file : FileAccess) -> Vector3:
	return convert_from_quake_units(Vector3(file.get_float(), file.get_float(), file.get_float()))

static func read_vector_convert_unscaled(file : FileAccess) -> Vector3:
	return convert_normal_vector_from_quake(Vector3(file.get_float(), file.get_float(), file.get_float()))


func _import(source_file : String, save_path : String, options, r_platform_variants, r_gen_files):
	print("Attempting to import %s" % source_file)
	#print("Options: ", options)
	var material_path_pattern : String = options["material_path_pattern"]
	print("Material path pattern: ", material_path_pattern)
	var file := FileAccess.open(source_file, FileAccess.READ)

	if (!file):
		var error := FileAccess.get_open_error()
		print("Failed to open %s: %d" % [source_file, error])
		return error

	var root_node := Node3D.new()
	root_node.name = source_file.get_file().get_basename() # Get the file out of the path and remove file extension

	# Read the header
	var bsp_version := file.get_32()
	print("BSP version: %d\n" % bsp_version)
	var entity_offset := file.get_32()
	var entity_size := file.get_32()
	var planes_offset := file.get_32()
	var planes_size := file.get_32()
	var textures_offset := file.get_32()
	var textures_size := file.get_32()
	var verts_offset := file.get_32()
	var verts_size := file.get_32()
	var vis_offset := file.get_32()
	var vis_size := file.get_32()
	var nodes_offset := file.get_32()
	var nodes_size := file.get_32()
	var texinfo_offset := file.get_32()
	var texinfo_size := file.get_32()
	var faces_offset := file.get_32()
	var faces_size := file.get_32()
	var lightmaps_offset := file.get_32()
	var lightmaps_size := file.get_32()
	var clipnodes_offset := file.get_32()
	var clipnodes_size := file.get_32()
	var leaves_offset := file.get_32()
	var leaves_size := file.get_32()
	var listfaces_size := file.get_32()
	var listfaces_offset := file.get_32()
	var edges_offset := file.get_32()
	var edges_size := file.get_32()
	var listedges_offset := file.get_32()
	var listedges_size := file.get_32()
	var models_offset := file.get_32()
	var models_size := file.get_32()
	
	# Read vertex data
	var verts : PackedVector3Array
	file.seek(verts_offset)
	var vert_data_left := verts_size
	var vertex_count := verts_size / (4 * 3)
	verts.resize(vertex_count)
	for i in vertex_count:
		verts[i] = convert_from_quake_units(Vector3(file.get_float(), file.get_float(), file.get_float()))
		#print("Vert: ", verts[i])

	#print("edges_offset: ", edges_offset)
	file.seek(edges_offset)
	var edges_data_left := edges_size
	var edges := []
	while (edges_data_left > 0):
		var edge := BSPEdge.new()
		edges_data_left -= edge.read_edge(file)
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
	
	
	var plane_normals : PackedVector3Array
	var num_planes := planes_size / (4 * 5) # vector, float, and int32
	plane_normals.resize(num_planes)
	file.seek(planes_offset)
	for i in num_planes:
		var quake_plane_normal := Vector3(file.get_float(), file.get_float(), file.get_float())
		#print("Quake normal: ", quake_plane_normal)
		plane_normals[i] = convert_normal_vector_from_quake(quake_plane_normal)
		file.get_float() # dist
		file.get_32() # type

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
			textures[i].read_texture(file, material_path_pattern, options.texture_material_rename)
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
	var model_data_size := BSPModelData.get_data_size()
	var num_models := models_size / model_data_size
	var model_data := []
	model_data.resize(num_models)
	for i in num_models:
		model_data[i] = BSPModelData.new()
		file.seek(models_offset + model_data_size * i) # We'll skip around in the file loading data
		model_data[i].read_model(file)

	file.seek(faces_offset)
	var face_data_left := faces_size
	var bsp_face := BSPFace.new()
	var begun := false
	var previous_tex_name := "UNSET"
	var surface_tools := {}
	
	for model_index in num_models:
		if (model_index == 0): # Only import the worldspawn for now, since doors and triggers will just block movement
			var bsp_model : BSPModelData = model_data[model_index]
			var face_size := BSPFace.get_data_size()
			file.seek(faces_offset + bsp_model.face_index * face_size)
			var num_faces := bsp_model.face_count
			for face_index in num_faces:
				bsp_face.read_face(file)
				# Get the texture from the face
				var tex_info : BSPTextureInfo = textureinfos[bsp_face.texinfo_id]
				var texture : BSPTexture = textures[tex_info.texture_index]
				var surf_tool : SurfaceTool
				if (surface_tools.has(texture.name)):
					surf_tool = surface_tools[texture.name]
				else:
					surf_tool = SurfaceTool.new()
					surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					surf_tool.set_material(texture.material)
					# TODO: Set material to a resource that matches the texture name.
					surface_tools[texture.name] = surf_tool
				
				#print("plane id: ", bsp_face.plane_id)
				#print("face edge count: ", bsp_face.num_edges)
				var edge_list_index_start := bsp_face.edge_list_id
				#print("edge list index start: ", edge_list_index_start)
				var i := 0
				var face_verts : PackedVector3Array
				face_verts.resize(bsp_face.num_edges)
				var face_normals : PackedVector3Array
				face_normals.resize(bsp_face.num_edges)
				var face_normal := plane_normals[bsp_face.plane_id]
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
				var tex_scale_x := 1.0 / (UNIT_SCALE * tex_width)
				var tex_scale_y := 1.0 / (UNIT_SCALE * tex_height)
				#print("normal: ", face_normal)
				for edge_list_index in range(edge_list_index_start, edge_list_index_start + bsp_face.num_edges):
				#for edge_list_index in range(edge_list_index_start + bsp_face.num_edges - 1, edge_list_index_start - 1, -1): # Need to go in reverse order
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
			#surf_tool.generate_normals()
	
	var mesh_instance := MeshInstance3D.new()
	
	# Create a mesh out of all the surfaces
	var array_mesh : ArrayMesh = null
	for texture_name in surface_tools:
		var surf_tool : SurfaceTool = surface_tools[texture_name]
		#print("surf_tool: ", surf_tool, " tex name: ", texture_name)
		surf_tool.generate_tangents()
		array_mesh = surf_tool.commit(array_mesh)
	mesh_instance.mesh = array_mesh
	mesh_instance.name = "mesh"
	root_node.add_child(mesh_instance)
	mesh_instance.owner = root_node
	#print("face_data_left: ", face_data_left)

	# Collision.
	# Could ultimately read the clip stuff and create convex shapes, but just going to use triangle mesh collision for now.
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "collision_shape"
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	var static_body := StaticBody3D.new()
	static_body.name = "static_body"
	root_node.add_child(static_body)
	static_body.owner = root_node
	static_body.add_child(collision_shape)
	collision_shape.owner = root_node
	# Apparently we have to let the gc handle this autamically now: file.close()

	var packed_scene := PackedScene.new()
	if (packed_scene.pack(root_node)):
		print("Failed to pack scene.")
		return
	print("Saving to %s.%s" % [save_path, _get_save_extension()])
	return ResourceSaver.save(packed_scene, "%s.%s" % [save_path, _get_save_extension()])

