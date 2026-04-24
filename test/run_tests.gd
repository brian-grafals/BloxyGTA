extends Node

const CarScript = preload("res://scripts/car.gd")

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	_run_all_tests()
	print("=== Results: %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _run_all_tests() -> void:
	# torque_at_speed
	_check("torque at zero speed",
		_approx(CarScript.torque_at_speed(0.0, 22.0, 14.0, 0.55), 14.0))
	_check("torque at max speed",
		_approx(CarScript.torque_at_speed(22.0, 22.0, 14.0, 0.55), 0.0))
	_check("torque at falloff boundary",
		_approx(CarScript.torque_at_speed(22.0 * 0.55, 22.0, 14.0, 0.55), 14.0))
	var mid_spd: float = 22.0 * 0.55 + (22.0 - 22.0 * 0.55) * 0.5
	_check("torque at midpoint",
		_approx(CarScript.torque_at_speed(mid_spd, 22.0, 14.0, 0.55), 7.0))
	_check("torque symmetric for negative speed",
		_approx(CarScript.torque_at_speed(-15.0, 22.0, 14.0, 0.55),
				CarScript.torque_at_speed(15.0, 22.0, 14.0, 0.55)))

	# effective_steer_speed
	_check("steer at zero speed returns low",
		_approx(CarScript.effective_steer_speed(0.0, 2.4, 0.9, 8.0, 20.0), 2.4))
	_check("steer at max speed returns high",
		_approx(CarScript.effective_steer_speed(20.0, 2.4, 0.9, 8.0, 20.0), 0.9))
	_check("steer below falloff start returns low",
		_approx(CarScript.effective_steer_speed(5.0, 2.4, 0.9, 8.0, 20.0), 2.4))
	var mid_s: float = (8.0 + 20.0) * 0.5
	_check("steer at midpoint is interpolated",
		_approx(CarScript.effective_steer_speed(mid_s, 2.4, 0.9, 8.0, 20.0), (2.4 + 0.9) * 0.5))
	_check("steer symmetric for negative speed",
		_approx(CarScript.effective_steer_speed(-15.0, 2.4, 0.9, 8.0, 20.0),
				CarScript.effective_steer_speed(15.0, 2.4, 0.9, 8.0, 20.0)))

	# compute_grip
	_check("grip at t=1 equals normal_grip",
		_approx(CarScript.compute_grip(1.0, 0.85, 0.20), 0.85))
	_check("grip at t=0 equals handbrake_grip",
		_approx(CarScript.compute_grip(0.0, 0.85, 0.20), 0.20))
	_check("grip at t=0.5 is midpoint",
		_approx(CarScript.compute_grip(0.5, 0.85, 0.20), 0.525))
	_check("grip never exceeds normal_grip",
		CarScript.compute_grip(1.0, 0.85, 0.20) <= 0.85)
	_check("grip never below handbrake_grip",
		CarScript.compute_grip(0.0, 0.85, 0.20) >= 0.20)

func _check(name: String, passed: bool) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)

func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
	return abs(a - b) <= epsilon
