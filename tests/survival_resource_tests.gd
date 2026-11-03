extends SceneTree

const WorldScript = preload("res://scripts/world.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_food_acquisition()
	_test_no_food_no_recovery()
	_test_water_acquisition()
	_test_unreachable_water_no_recovery()
	_test_shared_resource_exhaustion()
	_test_no_stale_target_loop()
	_test_food_regrowth()
	_test_generated_food_resources()
	print("SUMMARY | failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _check(test_name: String, passed: bool, evidence: String) -> void:
	print("%s | %s | %s" % ["PASS" if passed else "FAIL", test_name, evidence])
	if not passed:
		failures += 1

func _new_test_world() -> Node:
	var world = WorldScript.new()
	world.rng.seed = 20261103
	for i in 20:
		var person: Dictionary = world._new_person(i)
		person.age_days = 1000
		person.life_days = 50000
		person.hunger = 0.0
		person.thirst = 0.0
		person.fatigue = 0.0
		person.position = Vector2(30, 30)
		world._ensure_person_survival_state(person)
		world.people.append(person)
	world.food_resources = world._make_food_resources()
	return world

func _test_food_acquisition() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	world.food_resources.append({"id": 101, "kind": "berries", "position": Vector2(34, 30), "quantity": 1, "max_quantity": 1, "regen_ticks": 0})
	var person: Dictionary = world.people[0]
	person.hunger = 90.0
	var start: Vector2 = person.position
	var moved := false
	var saw_travel := false
	var saw_eating := false
	for i in 20:
		world._step_world()
		moved = moved or person.position.distance_to(start) > 0.1
		saw_travel = saw_travel or person.survival_state == "travel_food"
		saw_eating = saw_eating or person.survival_state == "eating"
		if int(world.food_resources[0].quantity) == 0:
			break
	_check("A food acquisition", moved and saw_travel and saw_eating and int(world.food_resources[0].quantity) == 0 and float(person.hunger) < 90.35 and person.position.distance_to(Vector2(34, 30)) < 0.05, "travel=%s eating=%s moved=%s position=%s stock=%d hunger=%.2f" % [saw_travel, saw_eating, moved, person.position, world.food_resources[0].quantity, person.hunger])
	world.free()

func _test_no_food_no_recovery() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	var person: Dictionary = world.people[0]
	person.hunger = 90.0
	for i in 30:
		world._step_world()
	_check("B no food means no recovery", person.hunger >= 100.0 and person.survival_state != "eating", "hunger=%.2f state=%s" % [person.hunger, person.survival_state])
	world.free()

func _test_water_acquisition() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	var person: Dictionary = world.people[0]
	person.thirst = 90.0
	var saw_travel := false
	var saw_drinking := false
	for i in 24:
		world._step_world()
		saw_travel = saw_travel or person.survival_state == "travel_water"
		saw_drinking = saw_drinking or person.survival_state == "drinking"
		if float(person.thirst) < 90.42:
			break
	_check("C reachable water", saw_travel and saw_drinking and float(person.thirst) < 90.42 and absf(person.position.x - 41.0) < 0.05 and world._is_water_access_position(person.position), "travel=%s drinking=%s position=%s thirst=%.2f action=%s" % [saw_travel, saw_drinking, person.position, person.thirst, person.action])
	world.free()

func _test_unreachable_water_no_recovery() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	var person: Dictionary = world.people[0]
	person.position = Vector2(43, 30)
	person.thirst = 90.0
	world._step_world()
	_check("D unreachable water means no recovery", person.survival_state == "retry_water" and float(person.thirst) >= 90.42, "state=%s thirst=%.2f position=%s" % [person.survival_state, person.thirst, person.position])
	world.free()

func _test_shared_resource_exhaustion() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	world.food_resources.append({"id": 202, "kind": "berries", "position": Vector2(32, 30), "quantity": 1, "max_quantity": 1, "regen_ticks": 0})
	for i in 2:
		world.people[i].hunger = 90.0
	for i in 20:
		world._step_world()
	var first: Dictionary = world.people[0]
	var second: Dictionary = world.people[1]
	var one_fed_one_still_hungry := (float(first.hunger) < 90.35 and float(second.hunger) > 95.0) or (float(second.hunger) < 90.35 and float(first.hunger) > 95.0)
	_check("E exhausted food is unavailable to others", int(world.food_resources[0].quantity) == 0 and one_fed_one_still_hungry, "stock=%d hunger=(%.2f, %.2f) states=(%s, %s)" % [world.food_resources[0].quantity, first.hunger, second.hunger, first.survival_state, second.survival_state])
	world.free()

func _test_no_stale_target_loop() -> void:
	var world = _new_test_world()
	world.food_resources.clear()
	var person: Dictionary = world.people[0]
	person.hunger = 90.0
	for i in 1000:
		world._step_world()
	var stale_food_targets := 0
	for candidate in world.people:
		if candidate.survival_state == "travel_food" or candidate.survival_state == "eating":
			stale_food_targets += 1
	_check("F failed search does not retain stale target", stale_food_targets == 0 and float(person.hunger) == 100.0, "stale_food_targets=%d sample_state=%s target=%d hunger=%.2f cooldown=%d" % [stale_food_targets, person.survival_state, person.survival_target_id, person.hunger, person.survival_cooldown])
	world.free()

func _test_food_regrowth() -> void:
	var world = _new_test_world()
	world.food_resources[0].quantity = 0
	world.food_resources[0].regen_ticks = world.FOOD_REGEN_DAYS - 1
	world._regrow_food_resources()
	_check("food regrowth", int(world.food_resources[0].quantity) == 1, "regrown stock=%d" % world.food_resources[0].quantity)
	world.free()

func _test_generated_food_resources() -> void:
	var world = _new_test_world()
	var target: Dictionary = world._find_food_target(Vector2(30, 30))
	_check("generated food is available", world.food_resources.size() == 12 and not target.is_empty(), "patches=%d target_id=%s" % [world.food_resources.size(), str(target.get("id", "none"))])
	world.free()

