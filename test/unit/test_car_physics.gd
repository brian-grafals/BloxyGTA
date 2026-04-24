extends GdUnitTestSuite

const CarScript = preload("res://scripts/car.gd")

# ── torque_at_speed ──────────────────────────────────────────────────────────

func test_torque_at_zero_speed() -> void:
	assert_float(CarScript.torque_at_speed(0.0, 22.0, 14.0, 0.55)).is_equal_approx(14.0, 0.001)

func test_torque_at_max_speed() -> void:
	assert_float(CarScript.torque_at_speed(22.0, 22.0, 14.0, 0.55)).is_equal_approx(0.0, 0.001)

func test_torque_at_falloff_boundary() -> void:
	assert_float(CarScript.torque_at_speed(22.0 * 0.55, 22.0, 14.0, 0.55)).is_equal_approx(14.0, 0.001)

func test_torque_at_midpoint() -> void:
	var mid: float = 22.0 * 0.55 + (22.0 - 22.0 * 0.55) * 0.5
	assert_float(CarScript.torque_at_speed(mid, 22.0, 14.0, 0.55)).is_equal_approx(7.0, 0.001)

func test_torque_negative_mirrors_positive() -> void:
	assert_float(CarScript.torque_at_speed(-15.0, 22.0, 14.0, 0.55)).is_equal_approx(
		CarScript.torque_at_speed(15.0, 22.0, 14.0, 0.55), 0.001)

# ── effective_steer_speed ────────────────────────────────────────────────────

func test_steer_at_zero_speed() -> void:
	assert_float(CarScript.effective_steer_speed(0.0, 2.4, 0.9, 8.0, 20.0)).is_equal_approx(2.4, 0.001)

func test_steer_at_max_speed() -> void:
	assert_float(CarScript.effective_steer_speed(20.0, 2.4, 0.9, 8.0, 20.0)).is_equal_approx(0.9, 0.001)

func test_steer_below_falloff_start() -> void:
	assert_float(CarScript.effective_steer_speed(5.0, 2.4, 0.9, 8.0, 20.0)).is_equal_approx(2.4, 0.001)

func test_steer_at_midpoint() -> void:
	var mid: float = (8.0 + 20.0) * 0.5
	assert_float(CarScript.effective_steer_speed(mid, 2.4, 0.9, 8.0, 20.0)).is_equal_approx((2.4 + 0.9) * 0.5, 0.001)

func test_steer_negative_mirrors_positive() -> void:
	assert_float(CarScript.effective_steer_speed(-15.0, 2.4, 0.9, 8.0, 20.0)).is_equal_approx(
		CarScript.effective_steer_speed(15.0, 2.4, 0.9, 8.0, 20.0), 0.001)

# ── compute_grip ─────────────────────────────────────────────────────────────

func test_grip_at_t1_is_normal_grip() -> void:
	assert_float(CarScript.compute_grip(1.0, 0.85, 0.20)).is_equal_approx(0.85, 0.001)

func test_grip_at_t0_is_handbrake_grip() -> void:
	assert_float(CarScript.compute_grip(0.0, 0.85, 0.20)).is_equal_approx(0.20, 0.001)

func test_grip_at_midpoint() -> void:
	assert_float(CarScript.compute_grip(0.5, 0.85, 0.20)).is_equal_approx(0.525, 0.001)

func test_grip_never_exceeds_normal_grip() -> void:
	assert_bool(CarScript.compute_grip(1.0, 0.85, 0.20) <= 0.85).is_true()

func test_grip_never_below_handbrake_grip() -> void:
	assert_bool(CarScript.compute_grip(0.0, 0.85, 0.20) >= 0.20).is_true()
