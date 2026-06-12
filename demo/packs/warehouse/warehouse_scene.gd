extends Control

var _boxes: Array[TextureRect] = []
var _velocities: Array[Vector2] = []
var _spins: Array[float] = []


func _ready() -> void:
	clip_contents = true
	for index in range(26):
		var node: Node = get_node("Box%02d" % index)
		if node is TextureRect:
			var box: TextureRect = node
			_boxes.append(box)
			_velocities.append(Vector2(-120.0 + float((index * 37) % 240), -40.0 - float((index * 19) % 170)))
			_spins.append(-2.1 + float((index * 11) % 42) / 10.0)


func _process(delta: float) -> void:
	var bounds: Vector2 = size
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		bounds = Vector2(900.0, 520.0)

	for index in range(_boxes.size()):
		var box: TextureRect = _boxes[index]
		var velocity: Vector2 = _velocities[index]
		velocity.y += 520.0 * delta
		box.position += velocity * delta
		box.rotation += _spins[index] * delta
		if box.position.x < 22.0 or box.position.x + box.size.x > bounds.x - 22.0:
			velocity.x *= -0.86
			box.position.x = clampf(box.position.x, 22.0, bounds.x - 22.0 - box.size.x)
		if box.position.y + box.size.y > bounds.y - 34.0:
			velocity.y *= -0.72
			velocity.x *= 0.985
			box.position.y = bounds.y - 34.0 - box.size.y
		_velocities[index] = velocity
