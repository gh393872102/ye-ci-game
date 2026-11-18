extends RefCounted
## One damage entry for attacks, projectiles and destruction. No seat/mode branches.
static func damage(attack: float, defense: float, resistance := 1.0) -> float:
	return maxf(1.0, attack - defense * 0.5) * maxf(0.0, resistance)
