extends Node2D

# GF(3) arithmetic helpers
func gf3_add(a: int, b: int) -> int: return (a + b) % 3
func gf3_neg(a: int) -> int: return (3 - a) % 3
func gf3_label(a: int) -> String:
	if a == 0: return " 0"
	if a == 1: return "+1"
	return "-1"
func gf3_color(a: int) -> Color:
	if a == 0: return Color(0.88, 0.88, 0.88)      # white-ish
	if a == 1: return Color(0.76, 0.91, 0.55)       # green (+1)
	return Color(0.78, 0.57, 0.92)                   # purple (-1)
func gf3_glow(a: int) -> Color:
	if a == 0: return Color(0.5, 0.5, 0.5)
	if a == 1: return Color(0.63, 0.82, 0.44)
	return Color(0.63, 0.44, 0.75)

# Game state
var player_x := 400.0
var player_speed := 300.0
var beam_gf3 := 1  # 0, 1, or 2
var bullets := []
var enemies := []
var particles := []
var floating_texts := []
var score := 0
var wave := 1
var lives := 3
var combo := 0
var combo_timer := 0.0
var combo_mult := 1
var total_conversions := 0
var total_mismatches := 0
var spawn_timer := 0.0
var spawn_interval := 1.4
var enemies_spawned := 0
var enemies_per_wave := 8
var game_over := false
var fire_cooldown := 0.0

var SEXP_TEXTS := [
	"(list 1 2 3)", "(option Some)", "(record (x 1))", "(variant Foo)",
	"(tuple 1 \"a\")", "(array #[])", "(poly `Bar)", "(gadt T int)",
	"((malformed )", "( unbalanced))", "(((nested)))", "(sexp.opaque _)",
	"(@default 0)", "(of_sexp_error)", "(Sexp.t list)", "(ppx_deriving)",
	"(Golay [11,6,5])", "(NTRU lattice)", "(qutrit |0>+|1>+|2>)",
	"(Steiner triple)", "(AG(2,3) plane)", "(Setun balanced)",
]

var CONVERT_MSGS := [
	"@@deriving sexp", "sexp_of_t", "zero in GF(3)!", "converted!",
	"additive inverse!", "kernel element!"
]

var MISMATCH_MSGS := [
	"wrong field!", "not the inverse!", "mod 3 shift!", "try again!"
]

# GF(3) addition table for overlay
var ADD_TABLE := [[0,1,2],[1,2,0],[2,0,1]]

func _ready():
	get_window().title = "( SEXP DEFENDERS ) :: GF(3)"

func _process(delta):
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			restart()
		queue_redraw()
		return

	# Beam selection: Up=+1, Down=0, ui_end/PageDown=-1
	if Input.is_action_pressed("ui_up"):
		beam_gf3 = 1
	if Input.is_action_pressed("ui_down"):
		beam_gf3 = 0
	if Input.is_action_pressed("ui_page_down") or Input.is_action_pressed("ui_end"):
		beam_gf3 = 2

	# Player movement
	if Input.is_action_pressed("ui_left"):
		player_x -= player_speed * delta
	if Input.is_action_pressed("ui_right"):
		player_x += player_speed * delta
	player_x = clamp(player_x, 30, 770)

	# Fire cooldown
	fire_cooldown = max(0, fire_cooldown - delta)

	# Shooting
	if Input.is_action_pressed("ui_accept") and fire_cooldown <= 0:
		fire_cooldown = 0.16
		bullets.append({"x": player_x, "y": 545.0, "gf3": beam_gf3})

	# Spawning
	spawn_timer += delta
	if enemies_spawned < enemies_per_wave and spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		var txt = SEXP_TEXTS[randi() % SEXP_TEXTS.size()]
		var gf3val: int
		if wave <= 2:
			gf3val = 1 if randf() < 0.5 else 2
			if randf() < 0.15: gf3val = 0
		else:
			gf3val = randi() % 3
		var hp = 1
		var pts = 15
		var spd = 28.0 + wave * 7 + randf() * 15
		if wave % 3 == 0 and randf() < 0.4:
			hp = 2; pts = 30; spd *= 0.85
		if wave >= 5 and randf() < 0.2:
			hp = 2; pts = 30; spd *= 0.8
		if wave >= 8 and randf() < 0.15:
			hp = 3; pts = 60; spd *= 0.7
		enemies.append({
			"x": randf_range(80, 720), "y": -25.0,
			"text": txt, "gf3": gf3val,
			"hp": hp, "max_hp": hp,
			"speed": spd, "points": pts,
			"wobble": randf() * TAU, "flash": 0.0,
		})
		enemies_spawned += 1

	# Update bullets
	var new_bullets := []
	for b in bullets:
		b.y -= 480 * delta
		if b.y > -20:
			new_bullets.append(b)
	bullets = new_bullets

	# Update enemies
	var surviving := []
	for e in enemies:
		e.y += e.speed * delta
		e.wobble += 1.8 * delta
		e["render_x"] = e.x + sin(e.wobble) * 22.0
		if e.flash > 0: e.flash -= delta
		if e.y > 620:
			lives -= 1
			combo = 0; combo_mult = 1; combo_timer = 0
			floating_texts.append({"x": e.render_x, "y": 580.0,
				"text": "HEAP CORRUPTION!", "color": Color(1, 0.3, 0.3), "life": 1.2})
			if lives <= 0:
				game_over = true
			continue
		surviving.append(e)
	enemies = surviving

	# Collisions with GF(3) arithmetic
	for b in bullets:
		for e in enemies:
			if not e.has("render_x"): continue
			var dx = abs(b.x - e.render_x)
			var dy = abs(b.y - e.y)
			if dx < 55 and dy < 18:
				b.y = -100  # kill bullet
				var field_sum = gf3_add(e.gf3, b.gf3)
				if field_sum == 0:
					# Correct inverse!
					e.hp -= 1
					if e.hp <= 0:
						combo += 1
						combo_timer = 2.5
						combo_mult = min(9, 1 + combo / 2)
						var pts = e.points * combo_mult
						score += pts
						total_conversions += 1
						# Particles
						for i in range(8):
							var angle = TAU * i / 8.0
							particles.append({
								"x": e.render_x, "y": e.y,
								"vx": cos(angle) * 80, "vy": sin(angle) * 80,
								"life": 0.6,
								"char": ["(", ")", "0", "+", "-", "1", "@"][randi() % 7],
								"color": gf3_color(e.gf3),
							})
						var msg = CONVERT_MSGS[randi() % CONVERT_MSGS.size()]
						floating_texts.append({"x": e.render_x, "y": e.y - 15,
							"text": "+%d %s" % [pts, msg],
							"color": Color(0.76, 0.91, 0.55), "life": 1.2})
						e.y = 9999  # mark for removal
					else:
						e.gf3 = randi() % 3
						e.flash = 0.3
						floating_texts.append({"x": e.render_x, "y": e.y - 15,
							"text": "hit! now %s" % gf3_label(e.gf3),
							"color": Color(1, 0.8, 0.42), "life": 1.0})
				else:
					# Wrong beam - value shifts
					e.gf3 = field_sum
					e.flash = 0.2
					total_mismatches += 1
					combo = 0; combo_mult = 1; combo_timer = 0
					var msg = MISMATCH_MSGS[randi() % MISMATCH_MSGS.size()]
					floating_texts.append({"x": e.render_x, "y": e.y - 15,
						"text": "%s %s" % [gf3_label(e.gf3), msg],
						"color": Color(1, 0.54, 0.5), "life": 1.0})

	enemies = enemies.filter(func(e): return e.y < 700)
	bullets = bullets.filter(func(b): return b.y > -20)

	# Combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0; combo_mult = 1

	# Update particles
	var new_particles := []
	for p in particles:
		p.x += p.vx * delta
		p.y += p.vy * delta
		p.life -= delta
		if p.life > 0:
			new_particles.append(p)
	particles = new_particles

	# Update floating texts
	var new_ft := []
	for ft in floating_texts:
		ft.y -= 35 * delta
		ft.life -= delta
		if ft.life > 0:
			new_ft.append(ft)
	floating_texts = new_ft

	# Wave complete
	if enemies_spawned >= enemies_per_wave and enemies.size() == 0:
		wave += 1
		enemies_spawned = 0
		enemies_per_wave = 6 + wave * 2
		spawn_interval = max(0.35, 1.4 - wave * 0.07)
		var wlabel = "-- Golay Wave %d --" % wave if wave % 3 == 0 else "-- Wave %d --" % wave
		floating_texts.append({"x": 400.0, "y": 300.0,
			"text": wlabel, "color": Color(0.78, 0.57, 0.92), "life": 1.5})

	queue_redraw()

func _draw():
	# Background
	draw_rect(Rect2(0, 0, 800, 600), Color(0.04, 0.04, 0.1))

	if game_over:
		draw_string(ThemeDB.fallback_font, Vector2(300, 260), "SEGFAULT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 0.3, 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(200, 320),
			"Score: %d  Wave: %d  Conversions: %d" % [score, wave, total_conversions],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(260, 360),
			"Mismatches: %d" % total_mismatches,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(240, 400),
			"Press ENTER/SPACE to retry",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
		return

	# HUD
	draw_string(ThemeDB.fallback_font, Vector2(20, 25),
		"SCORE: %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
	draw_string(ThemeDB.fallback_font, Vector2(200, 25),
		"WAVE: %d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
	draw_string(ThemeDB.fallback_font, Vector2(370, 25),
		"BEAM: %s" % gf3_label(beam_gf3), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, gf3_color(beam_gf3))
	draw_string(ThemeDB.fallback_font, Vector2(530, 25),
		"COMBO: x%d" % combo_mult, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(0.97, 0.55, 0.42) if combo_mult > 1 else Color(0.5, 0.86, 0.79))
	var hearts = ""
	for i in range(lives): hearts += "♥ "
	draw_string(ThemeDB.fallback_font, Vector2(680, 25),
		hearts, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.4, 0.4))

	# Player
	var pcol = gf3_color(beam_gf3)
	draw_string(ThemeDB.fallback_font, Vector2(player_x - 15, 565),
		"(\\)", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, pcol)
	draw_string(ThemeDB.fallback_font, Vector2(player_x - 35, 580),
		"beam: %s" % gf3_label(beam_gf3), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pcol)
	draw_string(ThemeDB.fallback_font, Vector2(player_x - 55, 594),
		"ppx_sexp_conv :: GF(3)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.2, 0.35, 0.42))

	# Bullets
	for b in bullets:
		var bcol = gf3_color(b.gf3)
		draw_rect(Rect2(b.x - 2, b.y, 4, 16), bcol)
		draw_string(ThemeDB.fallback_font, Vector2(b.x - 8, b.y - 2),
			gf3_label(b.gf3), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, bcol)

	# Enemies
	for e in enemies:
		if not e.has("render_x"): continue
		var ecol = gf3_color(e.gf3)
		var flash_col = Color(1, 1, 1) if e.flash > 0 else ecol
		# GF(3) badge
		draw_string(ThemeDB.fallback_font, Vector2(e.render_x - 10, e.y - 10),
			gf3_label(e.gf3), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, flash_col)
		# Sexp text
		var hp_alpha = 0.5 + 0.5 * (float(e.hp) / float(e.max_hp))
		draw_string(ThemeDB.fallback_font, Vector2(e.render_x - 50, e.y + 6),
			e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(ecol.r, ecol.g, ecol.b, hp_alpha))
		# HP bar
		if e.max_hp > 1:
			var hp_ratio = float(e.hp) / float(e.max_hp)
			var bx = e.render_x - 30
			draw_rect(Rect2(bx, e.y + 12, 60, 3), Color(0.1, 0.1, 0.18))
			draw_rect(Rect2(bx, e.y + 12, 60 * hp_ratio, 3),
				Color(0.5, 0.86, 0.79) if hp_ratio > 0.5 else Color(0.97, 0.55, 0.42))

	# Particles
	for p in particles:
		var alpha = clamp(p.life / 0.6, 0, 1)
		draw_string(ThemeDB.fallback_font, Vector2(p.x, p.y),
			p.char, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(p.color.r, p.color.g, p.color.b, alpha))

	# Floating texts
	for ft in floating_texts:
		var alpha = clamp(ft.life / 1.2, 0, 1)
		draw_string(ThemeDB.fallback_font, Vector2(ft.x - 40, ft.y),
			ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(ft.color.r, ft.color.g, ft.color.b, alpha))

	# GF(3) addition table overlay (bottom-left)
	var ox = 14.0
	var oy = 510.0
	draw_string(ThemeDB.fallback_font, Vector2(ox, oy),
		"GF(3) +", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.38, 0.44))
	var labels = [" 0", "+1", "-1"]
	var vals = [0, 1, 2]
	for j in range(3):
		draw_string(ThemeDB.fallback_font, Vector2(ox + 26 + j * 22, oy),
			labels[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(gf3_color(vals[j]).r, gf3_color(vals[j]).g, gf3_color(vals[j]).b, 0.5))
	for i in range(3):
		draw_string(ThemeDB.fallback_font, Vector2(ox, oy + 14 + i * 14),
			labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(gf3_color(vals[i]).r, gf3_color(vals[i]).g, gf3_color(vals[i]).b, 0.5))
		for j in range(3):
			var result = ADD_TABLE[i][j]
			var a = 0.8 if result == 0 else 0.4
			draw_string(ThemeDB.fallback_font, Vector2(ox + 26 + j * 22, oy + 14 + i * 14),
				labels[result], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(gf3_color(result).r, gf3_color(result).g, gf3_color(result).b, a))

	# Beam selector (bottom-right)
	var sx = 740.0
	var sy = 520.0
	for i in range(3):
		var v = [1, 0, 2][i]
		var active = beam_gf3 == v
		var bcol = gf3_color(v)
		var a2 = 1.0 if active else 0.25
		var prefix = ">" if active else " "
		var suffix = "<" if active else ""
		draw_string(ThemeDB.fallback_font, Vector2(sx, sy + i * 18),
			"%s%s%s" % [prefix, labels[v], suffix], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(bcol.r, bcol.g, bcol.b, a2))

	# Golay wave indicator
	if wave % 3 == 0:
		draw_string(ThemeDB.fallback_font, Vector2(260, 595),
			"[ Golay Wave :: [11,6,5] over GF(3) ]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.57, 0.92, 0.3))

func restart():
	game_over = false
	score = 0; wave = 1; lives = 3
	combo = 0; combo_timer = 0; combo_mult = 1
	total_conversions = 0; total_mismatches = 0
	beam_gf3 = 1
	bullets.clear(); enemies.clear()
	particles.clear(); floating_texts.clear()
	enemies_spawned = 0
	enemies_per_wave = 8
	spawn_interval = 1.4
	fire_cooldown = 0
	player_x = 400.0
