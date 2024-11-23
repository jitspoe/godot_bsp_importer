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

@export var convertBSP : bool = false : set = set_convertBSP; 

@export var MeshPrim = Mesh.PRIMITIVE_TRIANGLES : set = setmp; func setmp(m): MeshPrim = m

@export var meshinstance : MeshInstance3D : set = setmi; func setmi(m): meshinstance = m



var geometry := {}

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
	
	var texture_info : int = 0 # uint16
	
	var lightmap_styles : Array = [null, null, null, null] # uint8 array
	var lightmap_offset : int = 0 # uint32

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
	
	#print(vertex_dir)
	
	geometry["vertex"] = get_verts(bytes(bsp_bytes, vertex_lmp))
	geometry["face"] = get_face_lump(bytes(bsp_bytes, face_lmp))
	
	geometry["edge"] = get_edges(bytes(bsp_bytes, edge_lmp))
	geometry["face_edge"] = get_face_edges(bytes(bsp_bytes, face_edge_lmp))
	
	print(geometry)
	
	var geometry = process_to_mesh_array(geometry)
	
	if meshinstance: meshinstance.mesh = create_mesh(geometry)
	


## takes the vertex, face, edge and face edge arrays and outputs an array of all the edge points.
func process_to_mesh_array(geometry : Dictionary) -> PackedVector3Array:
	var output_verts : PackedVector3Array = []
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
			
			if MeshPrim == Mesh.PRIMITIVE_LINES:
				output_verts.append_array([vert0, vert1])
			else:
				face_vert_list.append_array([vert0, vert1])
			
		if MeshPrim == Mesh.PRIMITIVE_TRIANGLES:
			
			for v in range(0, face_vert_list.size()-2):
				
				var vert0 = face_vert_list[0]
				var vert1 = face_vert_list[v + 1]
				var vert2 = face_vert_list[v + 2]
				
				
				output_verts.append_array([vert2, vert1, vert0])
				
				
				
			
			
			
		
		#print(face_edge_list)
		
		
	
	
	
	return output_verts



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
		
		
		
		faces.append(new_face)
		f += 1

	return faces

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
func create_mesh(verts : PackedVector3Array) -> Mesh:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(MeshPrim)
	for vert in range(0, verts.size(), 3):
		var a = verts[vert + 0]
		var b = verts[vert + 1]
		var c = verts[vert + 2]
		 
		var normal = (b - a).cross((c - a))
		
		mesh.surface_set_color(Color(randf(), randf(), randf()))
		
		mesh.surface_set_normal(normal)
		
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(b)
		mesh.surface_add_vertex(c)
		
	mesh.surface_end()

	return mesh

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
