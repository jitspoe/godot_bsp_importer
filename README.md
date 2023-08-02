# godot_bsp_importer
An importer addon to import Quake BSP files.

Simply put the addons/bsp_importer into your Godot project (include the addons directory), enable it in Project->Project Settings...->Plugins, and when you drag a Quake BSP file into your godot project directory, it will automatically convert it to a scene.

The materials assigned to the faces use the format "materials/{texture_name}_material.tres" by default, where texture_name is taken from the textures in the BSP file.  You can change the behavior by clicking on the bsp file in godot, then going to the "Import" tab and change the "Material Path Pattern".  You can also rename specific textures using the dictionary list below that.
