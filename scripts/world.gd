extends Node2D

const SAVE_PATH := "user://world.json"
const MAP_W := 64
const MAP_H := 64
const TILE_W := 22.0
const TILE_H := 11.0
const PANEL_X := 950.0
const PEOPLE_NAMES := ["阿禾", "石头", "小满", "青芽", "山果", "溪", "木木", "云生", "鹿鸣", "星", "禾苗", "阿石", "春枝", "远山", "小河", "果果", "风", "林间", "阿月", "晨光"]
const PERSONALITIES := ["好奇的探索者", "温和的照料者", "谨慎的观察者", "勇敢的猎手", "热情的交友者", "安静的独行者"]
const PERSONALITY_PROFILES := [
	{"curiosity": 88, "extroversion": 48, "courage": 65, "caution": 32, "independence": 70, "patience": 58},
	{"curiosity": 56, "extroversion": 82, "courage": 48, "caution": 58, "independence": 34, "patience": 84},
	{"curiosity": 64, "extroversion": 34, "courage": 35, "caution": 88, "independence": 52, "patience": 82},
	{"curiosity": 72, "extroversion": 42, "courage": 94, "caution": 22, "independence": 82, "patience": 62},
	{"curiosity": 62, "extroversion": 94, "courage": 58, "caution": 34, "independence": 38, "patience": 56},
	{"curiosity": 44, "extroversion": 22, "courage": 63, "caution": 66, "independence": 94, "patience": 78}
]
const TRAIT_LABELS := {"curiosity": "好奇", "extroversion": "外向", "courage": "勇气", "caution": "谨慎", "independence": "独立", "patience": "耐心"}
const ACTION_LABELS := {"explore_safe": "附近探索", "explore_risky": "远处探索", "social": "接近族人", "food": "寻找浆果", "water": "前往河边", "rest": "休息", "wait": "观察等待", "help": "寻求帮助"}
const SAFE_EXPLORE_OFFSETS := [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]
const FAR_EXPLORE_TARGETS := [Vector2i(8, 8), Vector2i(13, 54), Vector2i(54, 10), Vector2i(55, 54), Vector2i(6, 31), Vector2i(57, 30)]
const SKIN := [Color("#e9b887"), Color("#d99d71"), Color("#f0c49a"), Color("#c88760")]
const FOOD_HUNGER_THRESHOLD := 78.0
const WATER_THIRST_THRESHOLD := 78.0
const FOOD_RESTORE := 38.0
const WATER_RESTORE := 50.0
const FOOD_REGEN_DAYS := 24
const MOVE_SPEED := 1.0
const WATER_X_MIN := 42
const WATER_X_MAX := 46
const WATER_Y_MIN := 6
const WATER_Y_MAX := 57
const FOOD_POSITIONS := [Vector2(21, 16), Vector2(27, 20), Vector2(35, 18), Vector2(38, 28), Vector2(18, 31), Vector2(29, 39), Vector2(36, 35), Vector2(24, 46), Vector2(12, 24), Vector2(52, 15), Vector2(53, 38), Vector2(48, 50)]
const CARDINAL_DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var rng := RandomNumberGenerator.new()
var people: Array[Dictionary] = []
var food_resources: Array[Dictionary] = []
var decision_totals: Dictionary = {}
var paused := false
var speed := 1.0
var elapsed := 0.0
var sim_day := 1
var selected := -1
var tracked := -1
var camera_offset := Vector2.ZERO
var zoom := 1.0
var dragging := false
var last_mouse := Vector2.ZERO
var last_save_unix := 0
var log_lines: Array[String] = ["春天来到山谷。二十位族人开始了新的生活。"]

func _ready() -> void:
	rng.randomize()
	_load_world()
	set_process(true)
	set_process_input(true)

func _process(delta: float) -> void:
	if not paused:
		elapsed += delta * speed
		while elapsed >= 1.0:
			elapsed -= 1.0
			_step_world()
	if Time.get_unix_time_from_system() - last_save_unix >= 30:
		_save_world()
	queue_redraw()

func _step_world() -> void:
	sim_day += 1
	_regrow_food_resources()
	for i in people.size():
		var p := people[i]
		if p.age_days >= int(p.life_days):
			continue
		p.hunger = minf(100.0, float(p.hunger) + 0.35)
		p.thirst = minf(100.0, float(p.thirst) + 0.42)
		p.fatigue = minf(100.0, float(p.fatigue) + 0.22)
		p.social = minf(100.0, float(p.social) + 0.16)
		_update_person_action(p)
		p.age_days = int(p.age_days) + 1
	if sim_day % 24 == 0:
		log_lines.push_front("第%d天：族人们在森林与河边继续生活。" % sim_day)
		if log_lines.size() > 5:
			log_lines.pop_back()

func _update_person_action(p: Dictionary) -> void:
	var state := str(p.survival_state)
	if state == "travel_food":
		_advance_food_travel(p)
		return
	if state == "eating":
		_finish_eating(p)
		return
	if state == "travel_water":
		_advance_water_travel(p)
		return
	if state == "drinking":
		_finish_drinking(p)
		return
	if state == "retry_food" or state == "retry_water":
		if state == "retry_food" and float(p.thirst) >= WATER_THIRST_THRESHOLD:
			_clear_survival_target(p)
			_record_forced_survival_decision(p, "water", "口渴达到生存阈值，打断食物重试")
			_begin_water_search(p)
			return
		p.survival_cooldown = int(p.survival_cooldown) - 1
		_wander_person(p)
		if int(p.survival_cooldown) <= 0:
			p.survival_state = "idle"
			p.survival_cooldown = 0
		return
	if float(p.thirst) >= WATER_THIRST_THRESHOLD:
		_clear_utility_commitment(p)
		_record_forced_survival_decision(p, "water", "口渴需求优先于非生存行动")
		_begin_water_search(p)
		return
	if float(p.hunger) >= FOOD_HUNGER_THRESHOLD:
		_clear_utility_commitment(p)
		_record_forced_survival_decision(p, "food", "饥饿需求优先于非生存行动")
		_begin_food_search(p)
		return
	if _continue_utility_action(p):
		return
	if float(p.fatigue) > 80.0:
		p.action = "休息"
		p.fatigue = maxf(0.0, float(p.fatigue) - 30.0)
		return
	_choose_nonurgent_action(p)

func _choose_nonurgent_action(p: Dictionary) -> void:
	var candidates := _build_utility_candidates(p)
	var chosen := _weighted_utility_choice(candidates)
	if chosen.is_empty():
		p.action = "观察与等待"
		return
	p.utility_risk = float(chosen.get("risk", 0.0))
	_record_decision(p, candidates, str(chosen.id), str(chosen.reason))
	decision_totals[chosen.id] = int(decision_totals.get(chosen.id, 0)) + 1
	_start_utility_action(p, chosen)

func _build_utility_candidates(p: Dictionary) -> Array[Dictionary]:
	var traits: Dictionary = p.traits
	var curiosity := float(traits.curiosity)
	var extroversion := float(traits.extroversion)
	var courage := float(traits.courage)
	var caution := float(traits.caution)
	var independence := float(traits.independence)
	var patience := float(traits.patience)
	var social_need := float(p.social)
	var fatigue := float(p.fatigue)
	var goal := str(p.goal)
	var social_target := _nearest_person_index(p)
	var social_distance := 999.0
	if social_target >= 0:
		social_distance = p.position.distance_to(people[social_target].position)
	var safe_target := _best_exploration_target(p, false)
	var risky_target := _best_exploration_target(p, true)
	var food_distance := _nearest_food_distance(p.position)
	var water_distance := _water_distance_estimate(p.position)
	var candidates: Array[Dictionary] = []
	if not safe_target.is_empty():
		var safe_utility := 18.0 + curiosity * 0.38 + independence * 0.12 + patience * 0.09 + caution * 0.05 - float(safe_target.risk) * 8.0
		if goal.contains("探索"):
			safe_utility += 5.0
		candidates.append({"id": "explore_safe", "label": "附近探索", "utility": safe_utility, "reason": "好奇与独立倾向；低风险 %.2f" % safe_target.risk, "target": safe_target.target, "risk": safe_target.risk})
	if not risky_target.is_empty():
		var risk_value := float(risky_target.risk)
		var risky_utility := 8.0 + curiosity * 0.28 + independence * 0.10 + patience * 0.12 + risk_value * (courage * 0.45 - caution * 0.50) + risk_value * 5.0
		if goal.contains("探索"):
			risky_utility += 5.0
		candidates.append({"id": "explore_risky", "label": "远处探索", "utility": risky_utility, "reason": "风险 %.2f；勇气提高承受意愿，谨慎降低风险偏好" % risk_value, "target": risky_target.target, "risk": risk_value})
	var social_utility := 14.0 + extroversion * 0.48 + social_need * 0.25 - independence * 0.20 + maxf(0.0, 6.0 - social_distance) * 1.4
	if goal.contains("朋友"):
		social_utility += 5.0
	if social_target >= 0:
		candidates.append({"id": "social", "label": "接近族人", "utility": social_utility, "reason": "外向与社交需求；独立性降低主动接近倾向", "target_id": int(people[social_target].id), "risk": 0.0})
	else:
		candidates.append({"id": "social", "label": "接近族人", "utility": -100.0, "reason": "附近没有可接近的族人", "target_id": -1, "risk": 0.0})
	var food_utility := 8.0 + float(p.hunger) * 0.62 - food_distance * 0.25
	if food_distance < 0.0:
		food_utility = -100.0
	candidates.append({"id": "food", "label": "寻找浆果", "utility": food_utility, "reason": "饥饿 %.0f；最近资源距离 %.1f" % [p.hunger, food_distance], "risk": 0.0})
	var water_utility := 8.0 + float(p.thirst) * 0.65 - water_distance * 0.25
	if water_distance < 0.0:
		water_utility = -100.0
	candidates.append({"id": "water", "label": "前往河边", "utility": water_utility, "reason": "口渴 %.0f；河岸估算距离 %.1f" % [p.thirst, water_distance], "risk": 0.0})
	var rest_utility := 14.0 + fatigue * 0.55 + patience * 0.05
	candidates.append({"id": "rest", "label": "休息", "utility": rest_utility, "reason": "疲劳 %.0f；耐心略微延长休息" % fatigue, "risk": 0.0})
	var wait_utility := 10.0 + patience * 0.35 - curiosity * 0.08
	candidates.append({"id": "wait", "label": "观察与等待", "utility": wait_utility, "reason": "耐心提高等待与持续行动的意愿", "risk": 0.0})
	if float(p.health) < 65.0 and social_target >= 0:
		var help_utility := 14.0 + (100.0 - independence) * 0.42 + extroversion * 0.12 - social_distance * 0.2
		candidates.append({"id": "help", "label": "寻求同伴帮助", "utility": help_utility, "reason": "健康偏低；较低独立性提高求助意愿", "target_id": int(people[social_target].id), "risk": 0.0})
	return candidates

func _weighted_utility_choice(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var maximum := -INF
	for candidate in candidates:
		maximum = maxf(maximum, float(candidate.utility))
	var weights: Array[float] = []
	var total := 0.0
	for candidate in candidates:
		var weight := exp(clampf((float(candidate.utility) - maximum) / 10.0, -30.0, 0.0))
		weights.append(weight)
		total += weight
	var draw := rng.randf() * total
	for i in weights.size():
		draw -= weights[i]
		if draw <= 0.0:
			return candidates[i]
	return candidates.back()

func _best_exploration_target(p: Dictionary, risky: bool) -> Dictionary:
	var candidates: Array[Vector2i] = []
	if risky:
		candidates.assign(FAR_EXPLORE_TARGETS)
	else:
		var origin := Vector2i(roundi(p.position.x), roundi(p.position.y))
		for offset in SAFE_EXPLORE_OFFSETS:
			candidates.append(origin + offset)
	var best: Dictionary = {}
	var best_score := -INF
	for tile in candidates:
		if not _is_walkable_tile(tile):
			continue
		var risk: float = _exploration_risk(tile)
		var distance: float = p.position.distance_to(Vector2(tile))
		var score: float = -distance * 0.2 + risk * (float(p.traits.courage) * 0.35 - float(p.traits.caution) * 0.32)
		if not risky:
			score = -distance - risk * 2.0
		if score > best_score:
			best_score = score
			best = {"target": Vector2(tile), "risk": risk}
	return best

func _exploration_risk(tile: Vector2i) -> float:
	var camp_distance := Vector2(tile).distance_to(Vector2(29, 30))
	var edge_distance := mini(mini(tile.x, MAP_W - 1 - tile.x), mini(tile.y, MAP_H - 1 - tile.y))
	var risk := 0.12 + camp_distance / 45.0 * 0.55 + maxf(0.0, 12.0 - float(edge_distance)) / 12.0 * 0.3
	return clampf(risk, 0.1, 0.95)

func _nearest_person_index(p: Dictionary) -> int:
	var nearest := -1
	var best_distance := INF
	for i in people.size():
		var other := people[i]
		if int(other.id) == int(p.id) or int(other.age_days) >= int(other.life_days):
			continue
		var distance: float = p.position.distance_to(other.position)
		if distance < best_distance:
			best_distance = distance
			nearest = i
	return nearest

func _nearest_food_distance(from: Vector2) -> float:
	var distance := INF
	for resource in food_resources:
		if int(resource.quantity) > 0:
			distance = minf(distance, from.distance_to(resource.position))
	return distance if is_finite(distance) else -1.0

func _water_distance_estimate(from: Vector2) -> float:
	var start := Vector2i(roundi(from.x), roundi(from.y))
	if not _is_walkable_tile(start):
		return -1.0
	var bank_x := WATER_X_MIN - 1 if start.x <= WATER_X_MIN else WATER_X_MAX + 1
	return absf(float(start.x - bank_x)) + absf(float(start.y - clampi(start.y, WATER_Y_MIN, WATER_Y_MAX)))

func _start_utility_action(p: Dictionary, candidate: Dictionary) -> void:
	var action_id := str(candidate.id)
	p.utility_action = action_id
	p.utility_remaining = 1 + int(float(p.traits.patience) / 35.0)
	p.utility_target_id = int(candidate.get("target_id", -1))
	p.utility_target = candidate.get("target", Vector2.ZERO)
	p.utility_risk = float(candidate.get("risk", 0.0))
	p.utility_route = []
	if action_id == "food":
		_clear_utility_commitment(p)
		_begin_food_search(p)
		return
	if action_id == "water":
		_clear_utility_commitment(p)
		_begin_water_search(p)
		return
	if action_id == "explore_safe" or action_id == "explore_risky":
		var path := _find_path(p.position, p.utility_target)
		if not bool(path.reachable):
			_clear_utility_commitment(p)
			p.action = "观察与等待"
			return
		p.utility_route = path.steps
		p.utility_remaining = p.utility_route.size() + 1 + int(float(p.traits.patience) / 25.0)
		p.action = "探索森林"
	elif action_id == "social" or action_id == "help":
		var person_index := _person_index_by_id(int(p.utility_target_id))
		if person_index < 0:
			_clear_utility_commitment(p)
			return
		var social_path := _find_path(p.position, people[person_index].position)
		if not bool(social_path.reachable):
			_clear_utility_commitment(p)
			return
		p.utility_route = social_path.steps
		p.utility_remaining = maxi(1, p.utility_route.size()) + 1 + int(float(p.traits.patience) / 25.0)
		p.action = "接近族人" if action_id == "social" else "寻找同伴帮助"
	elif action_id == "rest":
		p.action = "休息"
	elif action_id == "wait":
		p.action = "观察与等待"

func _continue_utility_action(p: Dictionary) -> bool:
	var action_id := str(p.utility_action)
	if action_id == "":
		return false
	if int(p.utility_remaining) <= 0:
		_clear_utility_commitment(p)
		return false
	if action_id == "explore_safe" or action_id == "explore_risky":
		if not p.utility_route.is_empty():
			if not _move_route(p.utility_route, p):
				if p.utility_route.is_empty():
					_clear_utility_commitment(p)
					return false
			p.action = "探索森林"
		else:
			p.action = "观察新区域"
	elif action_id == "social" or action_id == "help":
		var target_index := _person_index_by_id(int(p.utility_target_id))
		if target_index < 0:
			_clear_utility_commitment(p)
			return false
		var target_person: Dictionary = people[target_index]
		var distance: float = p.position.distance_to(target_person.position)
		if distance > 1.8:
			var path := _find_path(p.position, target_person.position)
			if not bool(path.reachable):
				_clear_utility_commitment(p)
				return false
			p.utility_route = path.steps
			if not p.utility_route.is_empty():
				_move_route(p.utility_route, p)
			p.action = "接近%s" % target_person.name if action_id == "social" else "前往%s处求助" % target_person.name
		else:
			if action_id == "social":
				p.action = "与%s交谈" % target_person.name
				p.social = maxf(0.0, float(p.social) - 3.0)
			else:
				p.action = "向%s求助" % target_person.name
	elif action_id == "rest":
		p.action = "休息"
		p.fatigue = maxf(0.0, float(p.fatigue) - 12.0)
	elif action_id == "wait":
		p.action = "观察与等待"
	p.utility_remaining = int(p.utility_remaining) - 1
	if int(p.utility_remaining) <= 0:
		_clear_utility_commitment(p)
	return true

func _move_route(route: Array, p: Dictionary) -> bool:
	if route.is_empty():
		return true
	var next_tile: Vector2i = route[0]
	if not _is_walkable_tile(next_tile):
		route.clear()
		return false
	var destination := Vector2(next_tile)
	var distance: float = p.position.distance_to(destination)
	if distance <= MOVE_SPEED:
		p.position = destination
		route.pop_front()
	else:
		p.position += (destination - p.position).normalized() * MOVE_SPEED
	return route.is_empty()

func _person_index_by_id(person_id: int) -> int:
	for i in people.size():
		if int(people[i].id) == person_id and int(people[i].age_days) < int(people[i].life_days):
			return i
	return -1

func _clear_utility_commitment(p: Dictionary) -> void:
	p.utility_action = ""
	p.utility_remaining = 0
	p.utility_target_id = -1
	p.utility_route.clear()
	p.utility_target = Vector2.ZERO
	p.utility_risk = 0.0

func _record_forced_survival_decision(p: Dictionary, action_id: String, reason: String) -> void:
	var candidates := _build_utility_candidates(p)
	_record_decision(p, candidates, action_id, reason)

func _record_decision(p: Dictionary, candidates: Array[Dictionary], chosen_id: String, reason: String) -> void:
	var options: Array[Dictionary] = []
	for candidate in candidates:
		options.append({"id": candidate.id, "label": candidate.label, "utility": snappedf(float(candidate.utility), 0.1), "reason": candidate.reason})
	p.last_decision = {"day": sim_day, "person": p.name, "traits": p.traits.duplicate(true), "needs": {"hunger": p.hunger, "thirst": p.thirst, "fatigue": p.fatigue, "social": p.social, "health": p.health}, "options": options, "chosen": chosen_id, "reason": reason, "risk": float(p.get("utility_risk", 0.0))}
	if selected >= 0 and selected < people.size() and int(people[selected].id) == int(p.id):
		print("[UtilityAI] " + JSON.stringify(p.last_decision))

func _begin_food_search(p: Dictionary) -> void:
	var target := _find_food_target(p.position)
	if target.is_empty():
		_enter_search_cooldown(p, "retry_food", "暂时找不到浆果")
		return
	p.survival_state = "travel_food"
	p.survival_target_id = int(target.id)
	p.survival_route = target.route
	p.action = "前往浆果丛"

func _advance_food_travel(p: Dictionary) -> void:
	var resource_index := _food_resource_index(int(p.survival_target_id))
	if resource_index < 0 or int(food_resources[resource_index].quantity) <= 0:
		_enter_search_cooldown(p, "retry_food", "浆果已耗尽，继续寻找")
		return
	var target_position: Vector2 = food_resources[resource_index].position
	if not _move_along_route(p):
		if p.survival_route.is_empty() and p.position.distance_to(target_position) > 0.05:
			_enter_search_cooldown(p, "retry_food", "无法抵达浆果丛，继续寻找")
		return
	if p.position.distance_to(target_position) <= 0.05:
		p.survival_state = "eating"
		p.action = "采集浆果"
	elif p.survival_route.is_empty():
		_enter_search_cooldown(p, "retry_food", "无法抵达浆果丛，继续寻找")

func _finish_eating(p: Dictionary) -> void:
	var resource_index := _food_resource_index(int(p.survival_target_id))
	if resource_index < 0 or int(food_resources[resource_index].quantity) <= 0:
		_enter_search_cooldown(p, "retry_food", "浆果已耗尽，继续寻找")
		return
	var target_position: Vector2 = food_resources[resource_index].position
	if p.position.distance_to(target_position) > 0.05:
		_enter_search_cooldown(p, "retry_food", "离开浆果丛，重新寻找")
		return
	food_resources[resource_index].quantity = int(food_resources[resource_index].quantity) - 1
	p.hunger = maxf(0.0, float(p.hunger) - FOOD_RESTORE)
	p.action = "食用浆果"
	_clear_survival_target(p)

func _begin_water_search(p: Dictionary) -> void:
	var target := _find_water_target(p.position)
	if target.is_empty():
		_enter_search_cooldown(p, "retry_water", "暂时无法抵达水源")
		return
	p.survival_state = "travel_water"
	p.survival_target_id = -1
	p.survival_route = target.route
	p.action = "前往河边"

func _advance_water_travel(p: Dictionary) -> void:
	if not _move_along_route(p):
		if p.survival_route.is_empty():
			_enter_search_cooldown(p, "retry_water", "无法抵达河边，稍后再找")
		return
	if _is_water_access_position(p.position):
		p.survival_state = "drinking"
		p.action = "在河边饮水"
	elif p.survival_route.is_empty():
		_enter_search_cooldown(p, "retry_water", "无法抵达河边，稍后再找")

func _finish_drinking(p: Dictionary) -> void:
	if not _is_water_access_position(p.position):
		_enter_search_cooldown(p, "retry_water", "离开河边，重新寻找水源")
		return
	p.thirst = maxf(0.0, float(p.thirst) - WATER_RESTORE)
	p.action = "饮水"
	_clear_survival_target(p)

func _enter_search_cooldown(p: Dictionary, retry_state: String, action_name: String) -> void:
	p.survival_state = retry_state
	p.survival_target_id = -1
	p.survival_route.clear()
	p.survival_cooldown = 6
	p.action = action_name

func _clear_survival_target(p: Dictionary) -> void:
	p.survival_state = "idle"
	p.survival_target_id = -1
	p.survival_route.clear()
	p.survival_cooldown = 0

func _move_along_route(p: Dictionary) -> bool:
	return _move_route(p.survival_route, p)

func _find_food_target(from: Vector2) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for resource in food_resources:
		if int(resource.quantity) > 0:
			candidates.append({"id": int(resource.id), "position": resource.position, "distance": from.distance_to(resource.position)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	for candidate in candidates:
		var route := _find_path(from, candidate.position)
		if bool(route.reachable):
			return {"id": int(candidate.id), "route": route.steps}
	return {}

func _find_water_target(from: Vector2) -> Dictionary:
	var start := Vector2i(roundi(from.x), roundi(from.y))
	if not _is_walkable_tile(start):
		return {}
	var side := WATER_X_MIN - 1 if start.x <= WATER_X_MIN else WATER_X_MAX + 1
	var bank := Vector2i(side, clampi(start.y, WATER_Y_MIN, WATER_Y_MAX))
	var route := _find_path(from, Vector2(bank))
	if not bool(route.reachable):
		return {}
	return {"route": route.steps}

func _find_path(from: Vector2, to: Vector2) -> Dictionary:
	var start := Vector2i(roundi(from.x), roundi(from.y))
	var goal := Vector2i(roundi(to.x), roundi(to.y))
	if not _is_walkable_tile(start) or not _is_walkable_tile(goal):
		return {"reachable": false, "steps": []}
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == goal:
			break
		for direction in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if not came_from.has(neighbor) and _is_walkable_tile(neighbor):
				came_from[neighbor] = current
				frontier.append(neighbor)
	if not came_from.has(goal):
		return {"reachable": false, "steps": []}
	var steps: Array[Vector2i] = []
	var current := goal
	while current != start:
		steps.push_front(current)
		current = came_from[current]
	if steps.is_empty():
		steps.append(goal)
	return {"reachable": true, "steps": steps}

func _is_walkable_tile(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= MAP_W or tile.y < 0 or tile.y >= MAP_H:
		return false
	return not _is_water_tile(tile) and not _is_mountain_tile(tile)

func _is_mountain_tile(tile: Vector2i) -> bool:
	return (tile.x * 17 + tile.y * 31) % 127 == 0

func _is_water_tile(tile: Vector2i) -> bool:
	return tile.x >= WATER_X_MIN and tile.x <= WATER_X_MAX and tile.y >= WATER_Y_MIN and tile.y <= WATER_Y_MAX

func _is_water_access_position(position: Vector2) -> bool:
	var tile := Vector2i(roundi(position.x), roundi(position.y))
	if not _is_walkable_tile(tile):
		return false
	for direction in CARDINAL_DIRECTIONS:
		if _is_water_tile(tile + direction):
			return true
	return false

func _food_resource_index(resource_id: int) -> int:
	for i in food_resources.size():
		if int(food_resources[i].id) == resource_id:
			return i
	return -1

func _total_food_stock() -> int:
	var total := 0
	for resource in food_resources:
		total += int(resource.quantity)
	return total

func _available_food_patches() -> int:
	var total := 0
	for resource in food_resources:
		if int(resource.quantity) > 0:
			total += 1
	return total

func _wander_person(p: Dictionary) -> void:
	var candidate: Vector2 = p.position + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	candidate.x = clampf(candidate.x, 5.0, 58.0)
	candidate.y = clampf(candidate.y, 5.0, 58.0)
	if _is_walkable_tile(Vector2i(roundi(candidate.x), roundi(candidate.y))):
		p.position = candidate

func _regrow_food_resources() -> void:
	for i in food_resources.size():
		var resource := food_resources[i]
		if int(resource.quantity) >= int(resource.max_quantity):
			resource.regen_ticks = 0
			continue
		resource.regen_ticks = int(resource.regen_ticks) + 1
		if int(resource.regen_ticks) >= FOOD_REGEN_DAYS:
			resource.quantity = int(resource.quantity) + 1
			resource.regen_ticks = 0

func _make_food_resources() -> Array[Dictionary]:
	var generated: Array[Dictionary] = []
	for i in FOOD_POSITIONS.size():
		generated.append({"id": i, "kind": "berries", "position": FOOD_POSITIONS[i], "quantity": 3, "max_quantity": 3, "regen_ticks": 0})
	return generated

func _ensure_person_survival_state(p: Dictionary) -> void:
	p.survival_state = "idle"
	p.survival_target_id = -1
	p.survival_route = []
	p.survival_cooldown = 0
	if not p.has("traits") or not p.traits is Dictionary:
		p.traits = _personality_profile(int(p.get("id", 0)))
	else:
		var defaults := _personality_profile(int(p.get("id", 0)))
		for key in defaults:
			p.traits[key] = clampi(int(p.traits.get(key, defaults[key])), 0, 100)
	p.utility_action = ""
	p.utility_remaining = 0
	p.utility_target_id = -1
	p.utility_route = []
	p.utility_target = Vector2.ZERO
	p.utility_risk = 0.0
	p.last_decision = {}

func _personality_profile(person_id: int) -> Dictionary:
	var profile: Dictionary = PERSONALITY_PROFILES[posmod(person_id, PERSONALITY_PROFILES.size())].duplicate(true)
	var trait_keys := ["curiosity", "extroversion", "courage", "caution", "independence", "patience"]
	for i in trait_keys.size():
		var key: String = trait_keys[i]
		var offset := posmod(person_id * (17 + i * 6) + i * 5, 13) - 6
		profile[key] = clampi(int(profile[key]) + offset, 0, 100)
	return profile

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 800)), Color("#18271f"))
	_draw_map()
	_draw_people()
	_draw_hud()

func _map_point(tile: Vector2) -> Vector2:
	var origin := Vector2(460, 405) + camera_offset
	return origin + Vector2((tile.x - tile.y) * TILE_W * zoom, (tile.x + tile.y - 64) * TILE_H * zoom)

func _draw_map() -> void:
	for y in MAP_H:
		for x in MAP_W:
			var p := _map_point(Vector2(x, y))
			if p.x < -40 or p.x > PANEL_X + 20 or p.y < -30 or p.y > 820:
				continue
			var color := Color("#6e9b56") if (x + y) % 5 != 0 else Color("#759f5d")
			if x > 41 and x < 47 and y > 5 and y < 58:
				color = Color("#4a96a1") if (x + y) % 4 != 0 else Color("#5aa6ad")
			if (x * 17 + y * 31) % 127 == 0:
				color = Color("#66785a")
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(TILE_W * zoom, TILE_H * zoom), p + Vector2(0, TILE_H * 2 * zoom), p + Vector2(-TILE_W * zoom, TILE_H * zoom)]), color)
	_draw_tree(Vector2(8, 12)); _draw_tree(Vector2(14, 9)); _draw_tree(Vector2(19, 18)); _draw_tree(Vector2(32, 11)); _draw_tree(Vector2(27, 30)); _draw_tree(Vector2(10, 38)); _draw_tree(Vector2(35, 45)); _draw_tree(Vector2(52, 21)); _draw_tree(Vector2(18, 53)); _draw_tree(Vector2(30, 55))
	_draw_food_resources()
	var camp := _map_point(Vector2(29, 30))
	draw_circle(camp + Vector2(0, 4), 24 * zoom, Color("#c47c49"))
	draw_circle(camp + Vector2(0, 4), 13 * zoom, Color("#f5c86a"))
	draw_string(ThemeDB.fallback_font, camp + Vector2(-30, 35), "营地", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(ThemeDB.fallback_font, _map_point(Vector2(44, 8)), "河流", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e0f0e5"))

func _draw_food_resources() -> void:
	for resource in food_resources:
		var at := _map_point(resource.position)
		var available := int(resource.quantity) > 0
		draw_circle(at + Vector2(0, -4) * zoom, 6 * zoom, Color("#4b7040") if available else Color("#52604a"))
		if available:
			var berries := mini(int(resource.quantity), 3)
			for berry_index in berries:
				draw_circle(at + Vector2(-3 + berry_index * 3, -8) * zoom, 1.8 * zoom, Color("#c84c52"))

func _draw_tree(tile: Vector2) -> void:
	var p := _map_point(tile)
	draw_rect(Rect2(p + Vector2(-3, -8) * zoom, Vector2(6, 17) * zoom), Color("#614735"))
	draw_circle(p + Vector2(0, -18) * zoom, 13 * zoom, Color("#315b3c"))
	draw_circle(p + Vector2(-6, -22) * zoom, 8 * zoom, Color("#477448"))
	draw_circle(p + Vector2(7, -24) * zoom, 7 * zoom, Color("#58804a"))

func _draw_people() -> void:
	var order := range(people.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(people[a].position.x) + float(people[a].position.y) < float(people[b].position.x) + float(people[b].position.y))
	for i in order:
		var p: Dictionary = people[i]
		var at := _map_point(p.position)
		var tint: Color = SKIN[int(p.skin) % SKIN.size()]
		if i == selected:
			draw_circle(at + Vector2(0, 1) * zoom, 10 * zoom, Color("#e8c977"))
			draw_arc(at + Vector2(0, 1) * zoom, 13 * zoom, 0, TAU, 24, Color("#f6e2a6"), 1.5 * zoom, true)
		draw_rect(Rect2(at + Vector2(-4, -9) * zoom, Vector2(8, 10) * zoom), Color("#76513d"))
		draw_circle(at + Vector2(0, -13) * zoom, 5 * zoom, tint)
		draw_rect(Rect2(at + Vector2(-5, -4) * zoom, Vector2(10, 3) * zoom), [Color("#d5bd86"), Color("#8da7a1"), Color("#c58d72"), Color("#a6b66f")][int(p.id) % 4])
		if i == tracked or i == selected:
			draw_string(ThemeDB.fallback_font, at + Vector2(-24, -23) * zoom, str(p.name), HORIZONTAL_ALIGNMENT_CENTER, 50, 11, Color.WHITE)

func _draw_hud() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 800)), Color("#111b1c"))
	draw_rect(Rect2(Vector2(0, 0), Vector2(1280, 54)), Color("#192b29"))
	draw_line(Vector2(0, 53), Vector2(1280, 53), Color("#53634c"), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(22, 34), "创世纪", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#f0e6c8"))
	draw_string(ThemeDB.fallback_font, Vector2(111, 33), "小小人生", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#b8c5ab"))
	_draw_stat_chip(Rect2(270, 11, 112, 31), "第 %d 天" % sim_day, Color("#33483d"))
	_draw_stat_chip(Rect2(389, 11, 112, 31), "族人 %d" % _living_count(), Color("#33483d"))
	_draw_stat_chip(Rect2(508, 11, 152, 31), "浆果 %d" % _total_food_stock(), Color("#4b4330"))
	_draw_button(Rect2(694, 10, 74, 32), "暂停" if not paused else "继续", paused)
	_draw_button(Rect2(778, 10, 48, 32), "1×", is_equal_approx(speed, 1.0))
	_draw_button(Rect2(833, 10, 48, 32), "5×", is_equal_approx(speed, 5.0))
	_draw_button(Rect2(888, 10, 48, 32), "20×", is_equal_approx(speed, 20.0))
	draw_rect(Rect2(PANEL_X, 54, 330, 746), Color("#1b2928"))
	draw_rect(Rect2(PANEL_X, 54, 330, 746), Color("#43584c"), false, 1.0)
	draw_rect(Rect2(PANEL_X, 54, 330, 48), Color("#243735"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 84), "族人档案", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#f0e6c8"))
	_draw_button(Rect2(PANEL_X + 194, 63, 110, 30), "保存世界", false)
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 122), "人物与需求 · 世界观察", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9cac9f"))
	if selected >= 0 and selected < people.size():
		_draw_person_panel(people[selected])
	else:
		_draw_world_overview()
	draw_line(Vector2(PANEL_X + 20, 620), Vector2(1260, 620), Color("#40544b"), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 648), "世界记事", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e7dfc6"))
	for i in mini(log_lines.size(), 4):
		draw_circle(Vector2(PANEL_X + 26, 675 + i * 28), 2.5, Color("#d6b86e"))
		draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 38, 679 + i * 28), log_lines[i], HORIZONTAL_ALIGNMENT_LEFT, 270, 11, Color("#bbc6b7"))
	draw_rect(Rect2(16, 748, 882, 34), Color("#182824"))
	draw_string(ThemeDB.fallback_font, Vector2(29, 770), "● 浆果丛", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#dfc878"))
	draw_string(ThemeDB.fallback_font, Vector2(128, 770), "● 河流", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#81bfc0"))
	draw_string(ThemeDB.fallback_font, Vector2(219, 770), "● 山石", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a6aaa0"))
	draw_string(ThemeDB.fallback_font, Vector2(355, 770), "滚轮缩放  ·  中键拖动  ·  空格暂停", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9caaa0"))

func _draw_stat_chip(rect: Rect2, label: String, color: Color) -> void:
	draw_rect(rect, color)
	draw_rect(rect, Color("#5a6b55"), false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 21), label, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 16), 13, Color("#eee7d0"))

func _draw_world_overview() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 166), "山谷概况", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#e7dfc6"))
	_draw_overview_card(Rect2(PANEL_X + 20, 181, 136, 72), "可采浆果", "%d / %d 丛" % [_available_food_patches(), food_resources.size()], Color("#d3bb73"))
	_draw_overview_card(Rect2(PANEL_X + 164, 181, 144, 72), "浆果库存", "%d 份" % _total_food_stock(), Color("#d3bb73"))
	draw_rect(Rect2(PANEL_X + 20, 269, 288, 72), Color("#223331"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 34, 294), "东侧河流", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#93c5c5"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 34, 319), "河岸可达 · 浆果每 24 日再生", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#aebcb1"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 382), "观察提示", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#e7dfc6"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 408), "选中族人可查看人格倾向、需求", HORIZONTAL_ALIGNMENT_LEFT, 286, 12, Color("#adb9ae"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 431), "以及本次决策的效用评分。", HORIZONTAL_ALIGNMENT_LEFT, 286, 12, Color("#adb9ae"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 477), "族人会自主决定探索、交谈、休息，", HORIZONTAL_ALIGNMENT_LEFT, 286, 12, Color("#adb9ae"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 22, 500), "生存需求达到阈值时优先寻找资源。", HORIZONTAL_ALIGNMENT_LEFT, 286, 12, Color("#adb9ae"))
	draw_rect(Rect2(PANEL_X + 20, 537, 288, 57), Color("#223331"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 34, 562), "离开后，世界仍会继续演化。", HORIZONTAL_ALIGNMENT_LEFT, 260, 12, Color("#e0d7bd"))
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_X + 34, 582), "当前第 %d 天" % sim_day, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb0a2"))

func _draw_overview_card(rect: Rect2, title: String, value: String, accent: Color) -> void:
	draw_rect(rect, Color("#293b35"))
	draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), accent)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#aebcaf"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 52), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#f0e6c8"))

func _draw_person_panel(p: Dictionary) -> void:
	var x := PANEL_X + 22.0
	draw_string(ThemeDB.fallback_font, Vector2(x, 158), "%s" % p.name, HORIZONTAL_ALIGNMENT_LEFT, 185, 21, Color("#f0e6c8"))
	draw_string(ThemeDB.fallback_font, Vector2(x, 180), "%d岁  ·  %s" % [int(p.age_days) / 360, p.personality], HORIZONTAL_ALIGNMENT_LEFT, 270, 11, Color("#aebcaf"))
	_draw_button(Rect2(PANEL_X + 226, 137, 80, 27), "跟踪中" if tracked == int(p.id) else "跟踪", tracked == int(p.id))
	var trait_keys := ["curiosity", "extroversion", "courage", "caution", "independence", "patience"]
	for i in trait_keys.size():
		var column := int(i / 3)
		var row := i % 3
		var tx := x + column * 144.0
		var ty := 204.0 + row * 24.0
		var key: String = trait_keys[i]
		var value := float(p.traits.get(key, 50))
		draw_string(ThemeDB.fallback_font, Vector2(tx, ty), "%s %d" % [TRAIT_LABELS[key], int(value)], HORIZONTAL_ALIGNMENT_LEFT, 72, 10, Color("#d1d6c9"))
		draw_rect(Rect2(tx + 75, ty - 7, 54, 4), Color("#33423b"))
		draw_rect(Rect2(tx + 75, ty - 7, 54 * value / 100.0, 4), Color("#d2b86f"))
	draw_rect(Rect2(x, 278, 286, 28), Color("#293a34"))
	draw_circle(Vector2(x + 12, 292), 3, Color("#d5b96c"))
	draw_string(ThemeDB.fallback_font, Vector2(x + 23, 297), "正在：%s" % p.action, HORIZONTAL_ALIGNMENT_LEFT, 255, 12, Color("#ede6d0"))
	var labels := ["饥饿", "口渴", "疲劳", "健康", "社交"]
	var keys := ["hunger", "thirst", "fatigue", "health", "social"]
	for i in labels.size():
		var y := 326 + i * 29
		draw_string(ThemeDB.fallback_font, Vector2(x, y + 11), labels[i], HORIZONTAL_ALIGNMENT_LEFT, 46, 10, Color("#aebcaf"))
		draw_rect(Rect2(x + 51, y, 190, 9), Color("#152220"))
		var value := clampf(float(p[keys[i]]), 0, 100)
		var bar_color := Color("#d27d5d") if keys[i] in ["hunger", "thirst", "fatigue"] else Color("#85b875")
		draw_rect(Rect2(x + 51, y, 190 * value / 100.0, 9), bar_color)
		draw_string(ThemeDB.fallback_font, Vector2(x + 252, y + 10), str(int(value)), HORIZONTAL_ALIGNMENT_LEFT, 28, 10, Color("#e4e4d4"))
	draw_string(ThemeDB.fallback_font, Vector2(x, 483), "愿望", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#aebcaf"))
	draw_string(ThemeDB.fallback_font, Vector2(x + 38, 483), str(p.goal), HORIZONTAL_ALIGNMENT_LEFT, 248, 11, Color("#e4d2a1"))
	_draw_decision_debug(p, Vector2(x, 506))

func _draw_decision_debug(p: Dictionary, origin: Vector2) -> void:
	var decision: Dictionary = p.get("last_decision", {})
	if decision.is_empty():
		draw_string(ThemeDB.fallback_font, origin + Vector2(0, 17), "决策评估将在下一次选择后显示。", HORIZONTAL_ALIGNMENT_LEFT, 282, 10, Color("#879a8e"))
		return
	draw_rect(Rect2(origin, Vector2(286, 91)), Color("#223330"))
	draw_string(ThemeDB.fallback_font, origin + Vector2(10, 17), "效用决策 · 第 %d 天" % int(decision.day), HORIZONTAL_ALIGNMENT_LEFT, 260, 10, Color("#d7c27f"))
	var options: Array = decision.options.duplicate()
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.utility) > float(b.utility))
	var shown := mini(options.size(), 3)
	for i in shown:
		var option: Dictionary = options[i]
		var text := "%s %0.1f" % [option.label, option.utility]
		draw_string(ThemeDB.fallback_font, origin + Vector2(10, 35 + i * 15), text, HORIZONTAL_ALIGNMENT_LEFT, 266, 9, Color("#b8c5b8"))
	draw_string(ThemeDB.fallback_font, origin + Vector2(10, 84), "选择：%s · %s" % [ACTION_LABELS.get(str(decision.chosen), decision.chosen), decision.reason], HORIZONTAL_ALIGNMENT_LEFT, 266, 9, Color("#efe7d0"))

func _draw_button(rect: Rect2, label: String, active := false) -> void:
	draw_rect(rect, Color("#d0b36a") if active else Color("#30453e"))
	draw_rect(rect, Color("#8b805c") if active else Color("#526459"), false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 21), label, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 12), 12, Color("#182421") if active else Color("#ebe5d2"))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(1.8, zoom * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(0.55, zoom / 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
	if event is InputEventMouseMotion and dragging:
		camera_offset += (event.position - last_mouse)
		last_mouse = event.position
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		paused = not paused

func _handle_click(pos: Vector2) -> void:
	if pos.y < 45 and pos.x >= 700 and pos.x < 768:
		paused = not paused; return
	if pos.y < 45 and pos.x >= 775 and pos.x < 823:
		speed = 1.0; return
	if pos.y < 45 and pos.x >= 828 and pos.x < 876:
		speed = 5.0; return
	if pos.y < 45 and pos.x >= 881 and pos.x < 929:
		speed = 20.0; return
	if pos.x >= PANEL_X + 194 and pos.x <= PANEL_X + 304 and pos.y < 100:
		_save_world(); return
	if selected >= 0 and pos.x >= PANEL_X + 226 and pos.x <= PANEL_X + 306 and pos.y >= 135 and pos.y <= 168:
		tracked = -1 if tracked == int(people[selected].id) else int(people[selected].id); return
	if pos.x >= PANEL_X or pos.y < 50:
		return
	var nearest := -1
	var distance := 24.0 * zoom
	for i in people.size():
		var d := _map_point(people[i].position).distance_to(pos)
		if d < distance:
			distance = d; nearest = i
	selected = nearest

func _living_count() -> int:
	var count := 0
	for p in people:
		if int(p.age_days) < int(p.life_days): count += 1
	return count

func _new_person(i: int) -> Dictionary:
	var age := rng.randi_range(1, 60)
	return {"id": i, "name": PEOPLE_NAMES[i], "age_days": age * 360, "life_days": rng.randi_range(65, 90) * 360, "position": Vector2(rng.randf_range(24, 36), rng.randf_range(24, 36)), "personality": PERSONALITIES[i % PERSONALITIES.size()], "traits": _personality_profile(i), "trait": ["好奇", "善良", "勇敢", "耐心", "外向", "獨立"][i % 6], "hunger": rng.randf_range(10, 60), "thirst": rng.randf_range(10, 60), "fatigue": rng.randf_range(5, 45), "health": rng.randf_range(72, 100), "social": rng.randf_range(12, 75), "action": "在营地休息", "goal": ["成为熟练的猎手", "照顾年幼的族人", "探索森林深处", "认识更多朋友", "找到安稳的住所"][i % 5], "skin": i % SKIN.size(), "survival_state": "idle", "survival_target_id": -1, "survival_route": [], "survival_cooldown": 0, "utility_action": "", "utility_remaining": 0, "utility_target_id": -1, "utility_route": [], "utility_target": Vector2.ZERO, "utility_risk": 0.0, "last_decision": {}}

func _save_world() -> void:
	var serial_people: Array = []
	for p in people:
		var q := p.duplicate(true)
		q.position = {"x": p.position.x, "y": p.position.y}
		q.erase("survival_route")
		q.survival_state = "idle"
		q.survival_target_id = -1
		q.survival_cooldown = 0
		q.erase("utility_route")
		q.erase("utility_target")
		q.erase("last_decision")
		q.utility_action = ""
		q.utility_remaining = 0
		q.utility_target_id = -1
		q.utility_risk = 0.0
		serial_people.append(q)
	var serial_resources: Array = []
	for resource in food_resources:
		var q := resource.duplicate(true)
		q.position = {"x": resource.position.x, "y": resource.position.y}
		serial_resources.append(q)
	var data := {"people": serial_people, "food_resources": serial_resources, "sim_day": sim_day, "log_lines": log_lines, "saved_unix": int(Time.get_unix_time_from_system())}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		last_save_unix = int(Time.get_unix_time_from_system())

func _load_world() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		for i in 20: people.append(_new_person(i))
		food_resources = _make_food_resources()
		last_save_unix = int(Time.get_unix_time_from_system())
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary or not parsed.has("people"):
		for i in 20: people.append(_new_person(i))
		food_resources = _make_food_resources()
		last_save_unix = int(Time.get_unix_time_from_system())
		return
	sim_day = int(parsed.get("sim_day", 1))
	log_lines.assign(parsed.get("log_lines", log_lines))
	for p in parsed.people:
		var q: Dictionary = p
		var at: Dictionary = q.position
		q.position = Vector2(float(at.x), float(at.y))
		_ensure_person_survival_state(q)
		people.append(q)
	if parsed.has("food_resources"):
		for resource in parsed.food_resources:
			var q: Dictionary = resource
			var at: Dictionary = q.position
			q.position = Vector2(float(at.x), float(at.y))
			food_resources.append(q)
	else:
		food_resources = _make_food_resources()
	var now := int(Time.get_unix_time_from_system())
	var away := clampi(now - int(parsed.get("saved_unix", now)), 0, 60 * 60 * 24 * 30)
	for tick in mini(away, 100000):
		_step_world()
	last_save_unix = now

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_world()
