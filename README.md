# godot_bsp_importer
An importer addon to import BSP files from the Quake family of engines.  Vanilla Quake1 BSP and the the extended Quake 1 BSP2 formats are fully supported.   Quake 2, Quake 3, and Half-Life (GoldSrc) format support is a work in progress, but should work for basic level geometry.

Simply put the addons/bsp_importer into your Godot project (include the addons directory), enable it in Project->Project Settings...->Plugins, and when you drag a Quake BSP file into your godot project directory, it will automatically convert it to a scene.

The materials assigned to the faces use the format "materials/{texture_name}_material.tres" by default, where texture_name is taken from the textures in the BSP file.  You can change the behavior by clicking on the bsp file in godot, then going to the "Import" tab and change the "Material Path Pattern".  You can also rename specific textures using the dictionary list below that.

For HL/GoldSrc .wad texture files, place the .wad files in "textures/wad".

Full guide on how to use the addon here: https://www.youtube.com/watch?v=RvCyg_lm_7w

A minor change since the video was made:

If you add a `set_import_value()` function, it should return true if the value was handled, otherwise it will call the default set() function.

For example, if you have something with speed and want to convert the units on import, you could do this:

```gdscript
@tool
@export var speed : float

func set_import_value(key : String, value : String) -> bool:
	if (key == "speed"):
		speed = value.to_float() / 32.0
		return true
	return false
```

Also, if any nodes have a `post_import()` function, this will be called after everything has been imported.

Note that any properties that need to be set via import need to have `@export` before them, and functions called by the import script need to have `@tool` set.

