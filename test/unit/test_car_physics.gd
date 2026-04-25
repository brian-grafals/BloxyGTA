extends GdUnitTestSuite

const CarScript = preload("res://scripts/car.gd")

# ── spring_rate ──────────────────────────────────────────────────────────────

func test_spring_rate_standard() -> void:
	# weight_per_wheel = 1500*9.8/4 = 3675 N, target_comp = 0.15*0.5 = 0.075 m
	assert_float(CarScript.spring_rate(1500.0, 4, 0.15, 0.5)).is_equal_approx(49000.0, 0.1)

func test_spring_rate_double_length_halves_stiffness() -> void:
	assert_float(CarScript.spring_rate(1500.0, 4, 0.30, 0.5)).is_equal_approx(24500.0, 0.1)

func test_spring_rate_lighter_car() -> void:
	assert_float(CarScript.spring_rate(1000.0, 4, 0.15, 0.5)).is_equal_approx(32666.67, 1.0)

func test_spring_rate_higher_resting_ratio_is_softer() -> void:
	var soft := CarScript.spring_rate(1500.0, 4, 0.15, 0.8)
	var stiff := CarScript.spring_rate(1500.0, 4, 0.15, 0.3)
	assert_bool(soft < stiff).is_true()

# ── damping_coeff ────────────────────────────────────────────────────────────

func test_damping_coeff_standard() -> void:
	# 0.45 * 2 * sqrt(49000 * 375) ≈ 3858
	var k := CarScript.spring_rate(1500.0, 4, 0.15, 0.5)
	assert_float(CarScript.damping_coeff(k, 375.0, 0.45)).is_equal_approx(3858.0, 5.0)

func test_damping_coeff_zero_ratio_returns_zero() -> void:
	var k := CarScript.spring_rate(1500.0, 4, 0.15, 0.5)
	assert_float(CarScript.damping_coeff(k, 375.0, 0.0)).is_equal_approx(0.0, 0.001)

func test_damping_coeff_scales_linearly_with_ratio() -> void:
	var k := CarScript.spring_rate(1500.0, 4, 0.15, 0.5)
	var c1 := CarScript.damping_coeff(k, 375.0, 0.3)
	var c2 := CarScript.damping_coeff(k, 375.0, 0.6)
	assert_float(c2 / c1).is_equal_approx(2.0, 0.001)

# ── compute_drag ─────────────────────────────────────────────────────────────

func test_drag_at_zero_speed() -> void:
	assert_float(CarScript.compute_drag(0.0, 1.225, 2.0, 0.35)).is_equal_approx(0.0, 0.001)

func test_drag_at_top_speed() -> void:
	# 0.5 * 1.225 * 22^2 * 2.0 * 0.35 ≈ 207.5
	assert_float(CarScript.compute_drag(22.0, 1.225, 2.0, 0.35)).is_equal_approx(207.5, 1.0)

func test_drag_obeys_v_squared_law() -> void:
	var d10 := CarScript.compute_drag(10.0, 1.225, 2.0, 0.35)
	var d20 := CarScript.compute_drag(20.0, 1.225, 2.0, 0.35)
	assert_float(d20 / d10).is_equal_approx(4.0, 0.001)
