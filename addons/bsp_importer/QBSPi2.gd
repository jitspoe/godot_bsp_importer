@tool class_name BSPi2 extends Node


## QBSPi2 (Quake BSPi Importer 2) By CSLR.


## based on documentation from:
## 
## https://jheriko-rtw.blogspot.com/2010/11/dissecting-quake-2-bsp-format.html
## https://www.flipcode.com/archives/Quake_2_BSP_File_Format.shtml
##
## I Hope This Isn't Gonna End Up GPL'd, If It Does I'm fine releasing it myself under GPL 

enum {LUMP_OFFSET, LUMP_LENGTH}

enum {
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

@export var textures_path : String = "res://materials/quake2_textures/"

@export var MeshPrim = Mesh.PRIMITIVE_TRIANGLES : set = setmp; func setmp(m): MeshPrim = m


var geometry := {}
var textures := {}

var entities := []

var models := []


## returns the raw bsp bytes.
func read_bsp(file) -> PackedByteArray: return FileAccess.get_file_as_bytes(file)

## Houses some face data, Most isnt being used but oh well.
class BSPFace:
	var plane : int = 0 # uint16
	var plane_side : int = 0 # uint16
	
	var first_edge : int = 0 # uint32
	var num_edges : int = 0 # uint16
	
	var texture_index : int = 0 # uint16
	
	var lightmap_styles : Array = [null, null, null, null] # uint8 array(?)
	var lightmap_offset : int = 0 # uint32
	
	var verts : PackedVector3Array = [] # For Mesh Construction

## Houses Texture Info
class BSPTexture extends Node:
	
	var u_axis : Vector3
	var u_offset : float 
	
	var v_axis : Vector3
	var v_offset : float 
	
	var flags : int # uint32
	var value : int # uint32
	
	var texture_path : String # uint32
	
	var next_textinfo : int # uint32

class BSPEntity extends Node3D:
	var default_class_data : Dictionary = {}
	func updatename() -> void: if default_class_data.has("classname"): self.name = default_class_data.get("classname")

class BSPPlane extends Node:
	var normal := Vector3.ZERO
	var distance : float = 0
	var type : int = 0 # ? 

class BSPBrush extends Node:
	var first_brush_side : int = 0
	var num_brush_side : int = 0
	var flags : int = 0

class BSPBrushSide extends Node:
	var plane_index : int = 0
	var texture_information : int = 0


func check_for_dir(dir):
	if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_absolute(dir)


func convertBSPtoScene(file_path : String) -> Node:
	check_for_dir("res://materials")
	check_for_dir("res://materials/quake2_textures/")
	
	prints("Converting File", file_path, ". Please Keep in Mind This is Still in Development and has some issues.")
	
	var file_name = file_path.get_base_dir()
	print(file_name)
	
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
	
	return CenterNode

## Central Function
func convert_to_mesh(file):
	var bsp_bytes : PackedByteArray = read_bsp(file).duplicate()
	
	var bsp_version = str(convert_from_uint32(bytes(bsp_bytes, range(4, 8))))
	var magic_num = bytes(bsp_bytes, range(0, 4)).get_string_from_utf8()
	
	prints("QBSPi2 Found BSP Version %s %s, Expecting Version IBSP 38" % [magic_num, bsp_version])
	
	var directory = fetch_directory(bsp_bytes)
	
	# i regret this code!
	var plane_lmp = range(directory[LUMP_PLANE].get(LUMP_OFFSET), directory[LUMP_PLANE].get(LUMP_OFFSET)+directory[LUMP_PLANE].get(LUMP_LENGTH))
	
	
	var vertex_lmp = range(directory[LUMP_VERTEX].get(LUMP_OFFSET), directory[LUMP_VERTEX].get(LUMP_OFFSET)+directory[LUMP_VERTEX].get(LUMP_LENGTH))
	var face_edge_lmp = range(directory[LUMP_FACE_EDGE].get(LUMP_OFFSET), directory[LUMP_FACE_EDGE].get(LUMP_OFFSET)+directory[LUMP_FACE_EDGE].get(LUMP_LENGTH))
	
	var face_lmp = range(directory[LUMP_FACE].get(LUMP_OFFSET), directory[LUMP_FACE].get(LUMP_OFFSET)+directory[LUMP_FACE].get(LUMP_LENGTH))
	var edge_lmp = range(directory[LUMP_EDGE].get(LUMP_OFFSET), directory[LUMP_EDGE].get(LUMP_OFFSET)+directory[LUMP_EDGE].get(LUMP_LENGTH))
	
	var texture_lmp = range(directory[LUMP_TEXTURE].get(LUMP_OFFSET), directory[LUMP_TEXTURE].get(LUMP_OFFSET)+directory[LUMP_TEXTURE].get(LUMP_LENGTH))
	var entity_lmp = range(directory[LUMP_ENT].get(LUMP_OFFSET), directory[LUMP_ENT].get(LUMP_OFFSET)+directory[LUMP_ENT].get(LUMP_LENGTH))
	
	var model_lmp = range(directory[LUMP_MODEL].get(LUMP_OFFSET), directory[LUMP_MODEL].get(LUMP_OFFSET)+directory[LUMP_MODEL].get(LUMP_LENGTH))
	
	var brush_lmp = range(directory[LUMP_BRUSH].get(LUMP_OFFSET), directory[LUMP_BRUSH].get(LUMP_OFFSET)+directory[LUMP_BRUSH].get(LUMP_LENGTH))
	var brush_side_lmp = range(directory[LUMP_BRUSH_SIDE].get(LUMP_OFFSET), directory[LUMP_BRUSH_SIDE].get(LUMP_OFFSET)+directory[LUMP_BRUSH_SIDE].get(LUMP_LENGTH))
	
	
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
	
	var mesh = create_mesh(geometry["face"])
	var mi = MeshInstance3D.new()
	var arm = ArrayMesh.new()
	
	
	for surface in mesh.get_surface_count():
		arm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
		arm.surface_set_material(surface, mesh.surface_get_material(surface))
	
	mi.mesh = arm
	
	return mi


## takes the vertex, face, edge and face edge arrays and outputs an array of all the edge points.
func process_to_mesh_array(geometry : Dictionary) -> void:
	var output_verts = []
	var face_vertex_indices = []
	
	var verts = geometry.get("vertex")
	var edges = geometry.get("edge")
	var face_edges = geometry.get("face_edge")
	
	for face_index in geometry.get("face"):
		var face = face_index as BSPFace
		var first_edge = face.first_edge
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
	var entities : Dictionary = process_json(ent_bytes.get_string_from_utf8())
	var entity_list = entities.get("data")
	
	var entity_output = []
	
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
		var flags = bytes(brush_bytes, range(index + 8, index + 12)).decode_u32(0)
		
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
		
		new_face.plane      = by.decode_u16(0)
		new_face.plane_side = by.decode_u16(2)
		new_face.first_edge = by.decode_u32(4)
		new_face.num_edges  = by.decode_u16(8)
		
		new_face.texture_index = by.decode_u16(10)
		
		faces.append(new_face)
		f += 1
	
	return faces

## returns texture lump
func get_texture_lmp(tex_bytes : PackedByteArray) -> Array:
	var count = tex_bytes.size() / 76
	prints("QBSPi2 Calculated Estimate of %s Texture References" % count)
	
	var output = []
	
	for b in range(0, tex_bytes.size(), 76):
		var BSPTI := BSPTexture.new()
		
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
		
		BSPTI.u_axis = Vector3(ux, uy, uz)
		BSPTI.u_offset = uoffset
		BSPTI.v_axis = Vector3(vx, vy, vz)
		BSPTI.v_offset = voffset
		
		BSPTI.flags = flags
		BSPTI.value = value
		
		BSPTI.texture_path = texture_path
		BSPTI.next_textinfo = next_texinfo
		
		BSPTI.name = str(BSPTI.texture_path)
		
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

func create_mesh(face_data : Array) -> Mesh:
	var mesh = ArrayMesh.new()
	var texture_list = textures["lumps"]
	var surface_list = {}
	var material_list = {}
	
	var missing_textures = []
	
	var mesh_arrays = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	
	for texture in texture_list:
		texture = texture as BSPTexture
		
		if not surface_list.has(texture.texture_path):
			var st =  SurfaceTool.new()
			surface_list[texture.texture_path] = st
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for face in face_data:
		face = face as BSPFace
		var texture =  textures["lumps"][face.texture_index] as BSPTexture
		
		if surface_list.has(texture.texture_path):
			var material = StandardMaterial3D.new()
			var p = textures_path + texture.texture_path + ".jpg"
			if not FileAccess.file_exists(p):
				if not missing_textures.has(p):
					missing_textures.append(p)
				#prints("QBSPi2 Cannot Find File '%s'. Ensure The File Exists." % (textures_path + texture.texture_path + ".jpg"))
			
			
			var matTexture = load("res://icon.svg")
			
			if FileAccess.file_exists(textures_path + texture.texture_path + ".jpg"):
				matTexture = load(textures_path + texture.texture_path + ".jpg")
			else:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = 0
			
			material.albedo_texture = matTexture
			
			var surface_tool = surface_list.get(texture.texture_path) as SurfaceTool
			
			material_list[surface_tool] = material
			
			
			var verts = face.verts
			if not material.albedo_color.a == 0:
				for vertIndex in range(0, verts.size(), 3):
					
					var v0 = verts[vertIndex + 0]
					var v1 = verts[vertIndex + 1]
					var v2 = verts[vertIndex + 2]
					
					var uv0 = get_uv(v0, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
					var uv1 = get_uv(v1, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
					var uv2 = get_uv(v2, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
					
					var plane = geometry["plane"][face.plane] as BSPPlane
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


func get_uv(vertex : Vector3, u_axis : Vector3, v_axis : Vector3, u_offset : float, v_offset : float, tex_size : Vector2) -> Vector2:
	var x = -(vertex.z / tex_size.y)
	var y = -(vertex.x / tex_size.x)
	var z = vertex.y / tex_size.y
	
	
	var u = x * u_axis.x + y * u_axis.y + z * u_axis.z + u_offset
	var v = x * v_axis.x + y * v_axis.y + z * v_axis.z + v_offset
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
