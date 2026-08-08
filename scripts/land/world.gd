var noise := FastNoiseLite.new()

func _ready():
	noise.seed = randi()
	noise.frequency = 0.003

	for x in range(0, 2000, 32):
		for y in range(0, 2000, 32):
			var value = noise.get_noise_2d(x, y)

			if value > 0.2:
				# здесь лес
				pass
			else:
				# здесь поле
				pass
