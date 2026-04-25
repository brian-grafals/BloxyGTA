extends Node

const CarScript = preload("res://scripts/car.gd")

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	_run_all_tests()
	print("=== Results: %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _run_all_tests() -> void:
	# spring_rate
	_check("spring_rate standard (1500 kg, 4w, 0.15 m, 0.5)",
		_approx(CarScript.spring_rate(1500.0, 4, 0.15, 0.5), 49000.0, 0.1))
	_check("spring_rate double rest_length halves stiffness",
		_approx(CarScript.spring_rate(1500.0, 4, 0.30, 0.5), 24500.0, 0.1))
	_check("spring_rate lighter car",
		_approx(CarScript.spring_rate(1000.0, 4, 0.15, 0.5), 32666.67, 1.0))
	_check("spring_rate higher resting_ratio is softer",
		CarScript.spring_rate(1500.0, 4, 0.15, 0.8) < CarScript.spring_rate(1500.0, 4, 0.15, 0.3))

	# damping_coeff
	var k: float = CarScript.spring_rate(1500.0, 4, 0.15, 0.5)
	_check("damping_coeff standard ≈ 3858",
		_approx(CarScript.damping_coeff(k, 375.0, 0.45), 3858.0, 5.0))
	_check("damping_coeff zero ratio = 0",
		_approx(CarScript.damping_coeff(k, 375.0, 0.0), 0.0))
	_check("damping_coeff scales linearly with ratio",
		_approx(CarScript.damping_coeff(k, 375.0, 0.6) /
				CarScript.damping_coeff(k, 375.0, 0.3), 2.0))

	# compute_drag
	_check("drag at zero speed = 0",
		_approx(CarScript.compute_drag(0.0, 1.225, 2.0, 0.35), 0.0))
	_check("drag at 22 m/s ≈ 207.5 N",
		_approx(CarScript.compute_drag(22.0, 1.225, 2.0, 0.35), 207.5, 1.0))
	_check("drag obeys v² law: drag(20)/drag(10) = 4",
		_approx(CarScript.compute_drag(20.0, 1.225, 2.0, 0.35) /
				CarScript.compute_drag(10.0, 1.225, 2.0, 0.35), 4.0))

func _check(name: String, passed: bool) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)

func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
	return abs(a - b) <= epsilon
