extends RefCounted
## Owns temporary per-surface materials, including attached equipment.

var _root: Node3D
var _shader: Shader
var _opacity := 0.65
var _saved: Array[Dictionary] = []

func setup(character_root: Node3D, shader: Shader, opacity: float) -> void:
    deactivate()
    _root = character_root
    _shader = shader
    _opacity = opacity

func activate() -> void:
    if _saved.is_empty():
        _apply(_root)

func _apply(node: Node) -> void:
    if node.is_queued_for_deletion():
        return
    if node is MeshInstance3D and node.mesh != null:
        var overrides: Array[Material] = []
        var whole_material: Material = node.material_override
        for surface in node.mesh.get_surface_count():
            overrides.append(node.get_surface_override_material(surface))
            var source: Material = node.get_active_material(surface)
            var material := ShaderMaterial.new()
            material.shader = _shader
            material.set_shader_parameter("opacity", _opacity)
            if source is BaseMaterial3D:
                material.set_shader_parameter("albedo_color", source.albedo_color)
                material.set_shader_parameter("albedo_texture", source.albedo_texture)
                material.set_shader_parameter("use_albedo_texture", source.albedo_texture != null)
                material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
                material.set_shader_parameter("roughness_value", source.roughness)
                material.set_shader_parameter("metallic_value", source.metallic)
            node.set_surface_override_material(surface, material)
        _saved.append({"mesh": node, "surfaces": overrides, "material": whole_material})
        node.material_override = null
    for child in node.get_children():
        _apply(child)

func deactivate() -> void:
    for entry in _saved:
        if not is_instance_valid(entry.mesh):
            continue
        for surface in entry.surfaces.size():
            entry.mesh.set_surface_override_material(surface, entry.surfaces[surface])
        entry.mesh.material_override = entry.material
    _saved.clear()
