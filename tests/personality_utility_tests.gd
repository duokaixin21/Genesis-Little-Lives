extends SceneTree

const WorldScript = preload("res://scripts/world.gd")
const TRIALS := 300

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_curiosity_exploration()
	_test_extroversion_social()
	_test_courage_and_caution_risk()
	_test_survival_priority()
	_test_population_distribution()
	_test_independence_solo_tendency()
	_test_patience_wait_and_commitment()
	_test_legacy_personality_migration()
	_test_decision_debug_record()
	print("SUMMARY | failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _check(name: String, passed: bool, evidence: String) -> void:
	print("%s | %s | %s" % ["PASS" if passed else "FAIL", name, evidence])
	if not passed:
		failures += 1

func _new_world() -> Node:
	var world = WorldScript.new()
	world.rng.seed = 66102
	for i in 20:
		var person: Dictionary = world._new_person(i)
		person.age_days = 1000
		person.life_days = 50000
		person.position = Vector2(30, 30)
		person.hunger = 30.0
		person.thirst = 30.0
		person.fatigue = 10.0
		person.social = 20.0
		person.health = 100.0
		world.people.append(person)
	world.food_resources = world._make_food_resources()
	return world

func _traits_for_experiment() -> Dictionary:
	return {"curiosity": 50, "extroversion": 50, "courage": 50, "caution": 50, "independence": 50, "patience": 50}

func _run_paired_trials(low_trait: String, low_value: int, high_trait: String, high_value: int) -> Array:
	var low_world = _new_world()
	var high_world = _new_world()
	var low_person: Dictionary = low_world.people[0]
	var high_person: Dictionary = high_world.people[0]
	low_person.traits = _traits_for_experiment()
	high_person.traits = _traits_for_experiment()
	low_person.traits[low_trait] = low_value
	high_person.traits[high_trait] = high_value
	var low_commitment := 0
	var high_commitment := 0
	for cycle in TRIALS:
		_reset_trial_person(low_person)
		_reset_trial_person(high_person)
		var seed_value := 7000 + cycle
		low_world.rng.seed = seed_value
		high_world.rng.seed = seed_value
		low_world._choose_nonurgent_action(low_person)
		high_world._choose_nonurgent_action(high_person)
		low_commitment += int(low_person.utility_remaining)
		high_commitment += int(high_person.utility_remaining)
	var low_counts: Dictionary = low_world.decision_totals.duplicate(true)
	var high_counts: Dictionary = high_world.decision_totals.duplicate(true)
	low_counts["_commitment_total"] = low_commitment
	high_counts["_commitment_total"] = high_commitment
	var result := [low_counts, high_counts]
	low_world.free()
	high_world.free()
	return result

func _reset_trial_person(person: Dictionary) -> void:
	person.position = Vector2(30, 30)
	person.hunger = 30.0
	person.thirst = 30.0
	person.fatigue = 10.0
	person.social = 20.0
	person.health = 100.0
	person.survival_state = "idle"
	person.survival_target_id = -1
	person.survival_route = []
	person.survival_cooldown = 0
	person.utility_action = ""
	person.utility_remaining = 0
	person.utility_target_id = -1
	person.utility_route = []
	person.utility_target = Vector2.ZERO
	person.utility_risk = 0.0

func _explore_count(counts: Dictionary) -> int:
	return int(counts.get("explore_safe", 0)) + int(counts.get("explore_risky", 0))

func _test_curiosity_exploration() -> void:
	var trials: Array = _run_paired_trials("curiosity", 5, "curiosity", 95)
	var low_count := _explore_count(trials[0])
	var high_count := _explore_count(trials[1])
	_check("A curiosity changes exploration", high_count > low_count + 60, "low=%d/%d (%.1f%%) high=%d/%d (%.1f%%)" % [low_count, TRIALS, 100.0 * low_count / TRIALS, high_count, TRIALS, 100.0 * high_count / TRIALS])

func _test_extroversion_social() -> void:
	var trials: Array = _run_paired_trials("extroversion", 5, "extroversion", 95)
	var low_count := int(trials[0].get("social", 0))
	var high_count := int(trials[1].get("social", 0))
	_check("B extroversion changes social approach", high_count > low_count + 60, "low=%d/%d (%.1f%%) high=%d/%d (%.1f%%)" % [low_count, TRIALS, 100.0 * low_count / TRIALS, high_count, TRIALS, 100.0 * high_count / TRIALS])

func _test_courage_and_caution_risk() -> void:
	var trials: Array = _run_paired_trials("courage", 95, "caution", 95)
	var bold_risky := int(trials[0].get("explore_risky", 0))
	var cautious_risky := int(trials[1].get("explore_risky", 0))
	var bold_total := _explore_count(trials[0])
	var cautious_total := _explore_count(trials[1])
	var bold_rate := float(bold_risky) / maxf(1.0, float(bold_total))
	var cautious_rate := float(cautious_risky) / maxf(1.0, float(cautious_total))
	_check("C courage/caution changes risky exploration", bold_rate > cautious_rate + 0.35, "bold risky=%d/%d (%.1f%%); cautious risky=%d/%d (%.1f%%)" % [bold_risky, bold_total, bold_rate * 100.0, cautious_risky, cautious_total, cautious_rate * 100.0])

func _test_survival_priority() -> void:
	var world = _new_world()
	var person: Dictionary = world.people[0]
	person.traits.curiosity = 100
	person.hunger = 100.0
	person.thirst = 10.0
	world._update_person_action(person)
	_check("D critical hunger outranks curiosity", person.survival_state == "travel_food" and person.action == "前往浆果丛", "curiosity=%d hunger=%.1f state=%s action=%s" % [person.traits.curiosity, person.hunger, person.survival_state, person.action])
	world.free()

func _test_population_distribution() -> void:
	var world = _new_world()
	var profile_signatures: Dictionary = {}
	for person in world.people:
		var traits: Dictionary = person.traits
		var signature := "%d,%d,%d,%d,%d,%d" % [traits.curiosity, traits.extroversion, traits.courage, traits.caution, traits.independence, traits.patience]
		profile_signatures[signature] = true
	for day in 240:
		world._step_world()
	var total := 0
	var nonzero := 0
	var distribution_counts: Dictionary = {}
	for action in world.decision_totals:
		var count := int(world.decision_totals[action])
		total += count
		if count > 0:
			nonzero += 1
		distribution_counts[action] = count
	var distribution: Array[String] = []
	for action in distribution_counts:
		var count := int(distribution_counts[action])
		distribution.append("%s=%d(%.1f%%)" % [action, count, 100.0 * count / maxf(1.0, float(total))])
	_check("E 20-person action distribution", profile_signatures.size() == 20 and total >= 100 and nonzero >= 3, "unique_profiles=%d decisions=%d distinct_actions=%d distribution=%s" % [profile_signatures.size(), total, nonzero, ", ".join(distribution)])
	world.free()

func _test_independence_solo_tendency() -> void:
	var trials: Array = _run_paired_trials("independence", 5, "independence", 95)
	var low_social := int(trials[0].get("social", 0))
	var high_social := int(trials[1].get("social", 0))
	var low_solo := _explore_count(trials[0])
	var high_solo := _explore_count(trials[1])
	_check("independence favors solo exploration", high_solo > low_solo and high_social < low_social, "low independent: solo=%d social=%d; high independent: solo=%d social=%d" % [low_solo, low_social, high_solo, high_social])

func _test_patience_wait_and_commitment() -> void:
	var trials: Array = _run_paired_trials("patience", 5, "patience", 95)
	var low_wait := int(trials[0].get("wait", 0))
	var high_wait := int(trials[1].get("wait", 0))
	var low_average := float(trials[0]._commitment_total) / TRIALS
	var high_average := float(trials[1]._commitment_total) / TRIALS
	_check("patience increases waiting and sustained actions", high_wait > low_wait + 30 and high_average > low_average + 1.0, "wait low=%d/%d high=%d/%d; average commitment low=%.2f high=%.2f days" % [low_wait, TRIALS, high_wait, TRIALS, low_average, high_average])

func _test_legacy_personality_migration() -> void:
	var world = _new_world()
	var legacy_person: Dictionary = {"id": 8, "name": "旧存档人物"}
	world._ensure_person_survival_state(legacy_person)
	var defaults: Dictionary = world._personality_profile(8)
	var complete := true
	for key in defaults:
		complete = complete and int(legacy_person.traits[key]) == int(defaults[key])
	var partial_person: Dictionary = {"id": 2, "traits": {"curiosity": 130, "patience": -10}}
	world._ensure_person_survival_state(partial_person)
	var clamped: bool = int(partial_person.traits.curiosity) == 100 and int(partial_person.traits.patience) == 0 and partial_person.traits.has("courage")
	_check("legacy personality data migration", complete and clamped, "missing profile generated; partial stats clamped and completed")
	world.free()

func _test_decision_debug_record() -> void:
	var world = _new_world()
	var person: Dictionary = world.people[0]
	world.rng.seed = 19
	world._choose_nonurgent_action(person)
	var decision: Dictionary = person.last_decision
	var valid: bool = decision.has("traits") and decision.has("needs") and decision.has("options") and decision.has("chosen") and decision.options.size() >= 5
	_check("decision debug record", valid, "person=%s chosen=%s options=%d" % [decision.get("person", "missing"), decision.get("chosen", "missing"), decision.get("options", []).size()])
	world.free()
