# godot_bsp_importer
An importer addon to import Quake BSP files.  Vanilla Quake1 BSP and the the extended Quake 1 BSP2 formats are supported. 

Simply put the addons/bsp_importer into your Godot project (include the addons directory), enable it in Project->Project Settings...->Plugins, and when you drag a Quake BSP file into your godot project directory, it will automatically convert it to a scene.

The materials assigned to the faces use the format "materials/{texture_name}_material.tres" by default, where texture_name is taken from the textures in the BSP file.  You can change the behavior by clicking on the bsp file in godot, then going to the "Import" tab and change the "Material Path Pattern".  You can also rename specific textures using the dictionary list below that.

Full guide on how to use the addon here: https://www.youtube.com/watch?v=RvCyg_lm_7w

A minor change since the video was made:

If you add a `set_import_value()` function, it should return true if the value was handled, otherwise it will call the default set() function.

For example, if you have something with speed and want to convert the units on import, you could do this:

```gdscript
@export var speed : float

func set_import_value(key : String, value : String) -> bool:
	if (key == "speed"):
		speed = value.to_float() / 32.0
		return true
	return false
```
