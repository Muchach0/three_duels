extends CPUParticles3D


func _ready() -> void:
    finished.connect(queue_free)
    restart()
