@tool class_name BSPi2 extends Node3D


## QBSPi2 (Quake BSPi Importer 2) By CSLR.


## based on documentation from:
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
	LUMP_LEAFFACETABLE,
	LUMP_LEAFBRUSHTABLE,
	LUMP_EDGE,
	LUMP_FACE_EDGE,
	LUMP_MODEL,
	LUMP_BRUSH,
	LUMP_BRUSHSIDE
}

@export var bsp_file : String
@export var textures_path : String = "res://Assets/textures/"
@export var texture_extension : String = ".jpg"

@export var convertBSP : bool = false : set = set_convertBSP; 

@export var MeshPrim = Mesh.PRIMITIVE_TRIANGLES : set = setmp; func setmp(m): MeshPrim = m

@export var meshinstance : MeshInstance3D : set = setmi; func setmi(m): meshinstance = m


var geometry := {}
var textures := {}

func set_convertBSP(c): 
	convertBSP = c
	if c: convert_to_mesh()
	convertBSP = false

## returns the raw bsp bytes.
func read_bsp(file) -> PackedByteArray: return FileAccess.get_file_as_bytes(file)

## Houses some face data, Most isnt being used but oh well.
class BSPFace:
	var plane : int = 0 # uint16
	var plane_side : int = 0 # uint16
	
	var first_edge : int = 0 # uint32
	var num_edges : int = 0 # uint16
	
	var texture_index : int = 0 # uint16
	
	var lightmap_styles : Array = [null, null, null, null] # uint8 array
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
	
	

## Central Function
func convert_to_mesh():
	var bsp_bytes : PackedByteArray = read_bsp(bsp_file).duplicate()
	
	await get_tree().create_timer(0.1).timeout
	
	var bsp_version = str(convert_from_uint32(bytes(bsp_bytes, range(4, 8))))
	var magic_num = bytes(bsp_bytes, range(0, 4)).get_string_from_utf8()
	
	prints("QBSPi2 Found BSP Version %s %s, Expecting Version IBSP 38, Version 46 May Not Be Supported Yet." % [magic_num, bsp_version])
	
	var directory = fetch_directory(bsp_bytes)
	
	# i regret this code!
	var vertex_lmp = range(directory[LUMP_VERTEX].get(LUMP_OFFSET), directory[LUMP_VERTEX].get(LUMP_OFFSET)+directory[LUMP_VERTEX].get(LUMP_LENGTH))
	var face_edge_lmp = range(directory[LUMP_FACE_EDGE].get(LUMP_OFFSET), directory[LUMP_FACE_EDGE].get(LUMP_OFFSET)+directory[LUMP_FACE_EDGE].get(LUMP_LENGTH))
	var face_lmp = range(directory[LUMP_FACE].get(LUMP_OFFSET), directory[LUMP_FACE].get(LUMP_OFFSET)+directory[LUMP_FACE].get(LUMP_LENGTH))
	var edge_lmp = range(directory[LUMP_EDGE].get(LUMP_OFFSET), directory[LUMP_EDGE].get(LUMP_OFFSET)+directory[LUMP_EDGE].get(LUMP_LENGTH))
	
	var texture_lmp = range(directory[LUMP_TEXTURE].get(LUMP_OFFSET), directory[LUMP_TEXTURE].get(LUMP_OFFSET)+directory[LUMP_TEXTURE].get(LUMP_LENGTH))
	
	geometry = {}
	textures = {}
	
	geometry["vertex"] = get_verts(bytes(bsp_bytes, vertex_lmp))
	geometry["face"] = get_face_lump(bytes(bsp_bytes, face_lmp))
	
	geometry["edge"] = get_edges(bytes(bsp_bytes, edge_lmp))
	geometry["face_edge"] = get_face_edges(bytes(bsp_bytes, face_edge_lmp))
	
	textures["lumps"] = get_texture_lmp(bytes(bsp_bytes, texture_lmp))
	
	process_to_mesh_array(geometry)
	
	if meshinstance: meshinstance.mesh = create_mesh(geometry["face"])
	


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
		
		var vec = Vector3(xbytes, zbytes, ybytes)
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

## creates and returns an ImmediateMesh, as of right now uses the edges but should use tris.
func create_mesh(data : Array) -> Mesh:
	var mesh = ImmediateMesh.new()
	var texture_list = textures["lumps"]
	var surface_list = {}
	
	if not textures_path.ends_with("/"): textures_path += "/"
	
	for texture in texture_list:
		texture = texture as BSPTexture
		if not surface_list.keys().has(texture):
			surface_list[texture] = []
	
	for face in data:
		face = face as BSPFace
		var surface_entry = texture_list[face.texture_index]
		surface_list[surface_entry].append(face)
	
	
	var sfc = 0 # surface count
	
	
	for surfaceTexture in surface_list:
		var surface = surface_list[surfaceTexture]
		if surface.size() > 0:
			var texture = surfaceTexture as BSPTexture
			mesh.surface_begin(MeshPrim)
			var material = StandardMaterial3D.new()
			if FileAccess.file_exists(textures_path + texture.texture_path + texture_extension):
				var matTexture = load(textures_path + texture.texture_path + texture_extension)
				material.albedo_texture = matTexture
				
				
				for face in surface:
					face = face as BSPFace
					var verts = face.verts as PackedVector3Array
					for vertIndex in range(0, verts.size(), 3):
						var v0 = verts[vertIndex + 0]
						var v1 = verts[vertIndex + 1]
						var v2 = verts[vertIndex + 2]
						
						var uv0 = get_uv(v0, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
						var uv1 = get_uv(v1, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
						var uv2 = get_uv(v2, texture.u_axis, texture.v_axis, texture.u_offset, texture.v_offset, matTexture.get_size())
						
						var normal = (v1 - v0).cross((v2 - v0))
						
						mesh.surface_set_normal(normal.normalized())
						
						mesh.surface_set_uv(uv0)
						mesh.surface_add_vertex(v0)
						
						mesh.surface_set_uv(uv1)
						mesh.surface_add_vertex(v1)
						
						mesh.surface_set_uv(uv2)
						mesh.surface_add_vertex(v2)
						
				
				
				
				mesh.surface_end()
				mesh.surface_set_material(sfc, material)
				sfc += 1
				
		
	
	
	
	
	return mesh

func get_uv(vertex : Vector3, u_axis : Vector3, v_axis : Vector3, u_offset : float, v_offset : float, tex_size : Vector2) -> Vector2:
	u_offset = 0
	v_offset = 0
	var x = vertex.x / tex_size.x
	var y = vertex.z / tex_size.y
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
