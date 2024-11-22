@tool class_name BSPi2 extends Node3D


## QBSPi2 (Quake BSP Importer 2) By CSLR.
## As of November 21 2024 Converts Quake 2 Geometry To Edges.


@export var bsp_file : String

@export var convertBSP : bool = false : set = set_convertBSP; 

@export var MeshPrim = Mesh.PRIMITIVE_LINES : set = setmp; func setmp(m): MeshPrim = m

@export var meshinstance : MeshInstance3D : set = setmi; func setmi(m): meshinstance = m

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
	
	var bsp_version = convert_from_uint32(bytes(bsp_bytes, range(4, 8)))
	
	prints("QBSPi2 Found BSP Version %s, Expecting Version 38 for Quake 2 BSP." % bsp_version)
	
	var directory = fetch_directory(bsp_bytes)
	
	var vkey = directory.keys()[2] # vertices
	
	var fkey = directory.keys()[6] # faces
	
	var ekey = directory.keys()[11] # edges
	var fekey = directory.keys()[12]  # face edges
	
	var vert_bytes = bytes(bsp_bytes, range(vkey, vkey+directory[vkey]))
	var face_bytes = bytes(bsp_bytes, range(fkey, fkey+directory[fkey]))
	
	var edge_bytes = bytes(bsp_bytes, range(ekey, ekey+directory[ekey]))
	var face_edge_bytes = bytes(bsp_bytes, range(fekey, fekey+directory[fekey]))
	
	var verts = get_verts(vert_bytes)
	var faces : Array[BSPFace] = get_face_lump(face_bytes)
	var edges = get_edges(edge_bytes)
	var face_edges = get_face_edges(face_edge_bytes)
	
	#for face in faces: prints(face.plane, face.plane_side, face.first_edge, face.num_edges, face.lightmap_styles, face.lightmap_offset) # for debugging
	
	var vertex_edge_array = process_to_edge_array(verts, faces, edges, face_edges)
	if meshinstance: meshinstance.mesh = create_mesh(vertex_edge_array, edges)
	

## takes the vertex, face, edge and face edge arrays and outputs an array of all the edge points.
func process_to_edge_array(verts : PackedVector3Array, face_array : Array, edge_array : Array, face_edge_array : Array) -> PackedVector3Array:
	var output_verts : PackedVector3Array = []
	
	for face in face_array:
		face = face as BSPFace
		var face_edges = range(face.first_edge, face.first_edge+face.num_edges)
		
		for face_edge in face_edges:
			if face_edge < edge_array.size():
				var edge = edge_array[abs(face_edge)]
				
				var edge0 = edge[0]
				var edge1 = edge[1]
				
				if face_edge > 0: 
					edge0 = edge[0]
					edge1 = edge[1]
				
				if face_edge < 0: 
					edge0 = edge[1]
					edge1 = edge[0]
				
				# divide to conversion from quake units to 1 meter
				
				var vert0 = Vector3(verts[edge0])
				var vert1 = Vector3(verts[edge1])
				
				
				output_verts.append_array([vert0, vert1])
	
	return output_verts 


## grabs the directory
func fetch_directory(bsp_bytes):
	prints("QBSPi2 BSP File Size:", bsp_bytes.size())
	var i = 0
	var dir = {}
	var dir_lump = bytes( bsp_bytes, range(8, (19*12) ))
	
	while i < dir_lump.size():
		if i+4 <= dir_lump.size() and i+8 <= dir_lump.size():
			var u32_key = convert_from_uint32(bytes(dir_lump, range(i, i+4)))
			var u32_value = convert_from_uint32(bytes(dir_lump, range(i+4, i+8)))
			dir[u32_key] = u32_value
		i += 8
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
		
		new_face.plane = bytes(lump_bytes, range(base_index + 0, base_index + 2)).decode_u16(0)
		new_face.plane_side = bytes(lump_bytes, range(base_index + 2, base_index + 4)).decode_u16(0)
		
		new_face.first_edge = bytes(lump_bytes, range(base_index + 4, base_index + 8)).decode_u32(0)
		new_face.num_edges = bytes(lump_bytes, range(base_index + 8, base_index + 10)).decode_u16(0)
		
		new_face.texture_info = bytes(lump_bytes, range(base_index + 10, base_index + 12)).decode_u16(0)
		
		var lms = []
		for i in [0, 1, 2, 3]: 
			lms.append(bytes(lump_bytes, range(base_index + 12 + i, base_index + 13 + i)).decode_u8(0))
		
		new_face.lightmap_styles = lms
		new_face.lightmap_offset = bytes(lump_bytes, range(base_index + 16, base_index + 20)).decode_u32(0)
		
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
		var edge_1 = bytes(edge_bytes, range(index + 0, index + 2)).decode_s16(0)
		var edge_2 = bytes(edge_bytes, range(index + 2, index + 4)).decode_s16(0)
		
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
func create_mesh(verts : PackedVector3Array, edges : Array) -> Mesh:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(MeshPrim)
	for vert in verts: mesh.surface_add_vertex(vert)
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
