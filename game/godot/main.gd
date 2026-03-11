extends Node2D

var player_x := 400.0
var player_speed := 300.0
var bullets := []
var enemies := []
var particles := []
var score := 0
var wave := 1
var lives := 3
var spawn_timer := 0.0
var spawn_interval := 1.2
var enemies_spawned := 0
var enemies_per_wave := 8
var game_over := false

var SEXP_TEXTS := [
	"(list 1 2 3)", "(option Some)", "(record (x 1))", "(variant Foo)",
	"(tuple 1 \"a\")", "(array #[])", "(poly `Bar)", "(gadt T int)",
	"((malformed )", "( unbalanced))", "(((nested)))", "(sexp.opaque _)",
	"(@default 0)", "(of_sexp_error)", "(Sexp.t list)", "(ppx_deriving)",
]

var CONVERT_MSGS := [
	"@@deriving sexp", "sexp_of_t", "t_of_sexp", "converted!", "well-typed!"
]

func _ready():
	get_window().title = "( SEXP DEFENDERS )"

func _process(delta):
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			restart()
		queue_redraw()
		return

	# Player movement
	if Input.is_action_pressed("ui_left"):
		player_x -= player_speed * delta
	if Input.is_action_pressed("ui_right"):
		player_x += player_speed * delta
	player_x = clamp(player_x, 30, 770)

	# Shooting
	if Input.is_action_pressed("ui_accept"):
		# Rate limit
		var can_fire := true
		for b in bullets:
			if b.y > 560:
				can_fire = false
				break
		if can_fire:
			bullets.append({"x": player_x, "y": 550.0})

	# Spawning
	spawn_timer += delta
	if enemies_spawned < enemies_per_wave and spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		var txt = SEXP_TEXTS[randi() % SEXP_TEXTS.size()]
		var hp = 1
		if wave >= 3 and randf() < 0.3:
			hp = 2
		enemies.append({
			"x": randf_range(80, 720),
			"y": -20.0,
			"text": txt,
			"hp": hp,
			"max_hp": hp,
			"speed": 40.0 + wave * 10 + randf() * 20,
			"wobble": randf() * TAU,
		})
		enemies_spawned += 1

	# Update bullets
	var new_bullets := []
	for b in bullets:
		b.y -= 500 * delta
		if b.y > -20:
			new_bullets.append(b)
	bullets = new_bullets

	# Update enemies
	var new_enemies := []
	for e in enemies:
		e.y += e.speed * delta
		e.wobble += 2.0 * delta
		e["render_x"] = e.x + sin(e.wobble) * 25.0
		if e.y > 620:
			lives -= 1
			if lives <= 0:
				game_over = true
			continue
		new_enemies.append(e)
	enemies = new_enemies

	# Collisions
	for b in bullets:
		for e in enemies:
			if not e.has("render_x"):
				continue
			var dx = abs(b.x - e.render_x)
			var dy = abs(b.y - e.y)
			if dx < 60 and dy < 15:
				b.y = -100  # kill bullet
				e.hp -= 1
				if e.hp <= 0:
					score += 10 * wave
					# Spawn particles
					for i in range(6):
						var angle = TAU * i / 6.0
						particles.append({
							"x": e.render_x, "y": e.y,
							"vx": cos(angle) * 80, "vy": sin(angle) * 80,
							"life": 0.6,
							"char": ["(", ")", "@", "s", "e", "x", "p"][randi() % 7],
						})
					e.y = 9999  # remove

	enemies = enemies.filter(func(e): return e.y < 700)
	bullets = bullets.filter(func(b): return b.y > -20)

	# Update particles
	var new_particles := []
	for p in particles:
		p.x += p.vx * delta
		p.y += p.vy * delta
		p.life -= delta
		if p.life > 0:
			new_particles.append(p)
	particles = new_particles

	# Wave complete
	if enemies_spawned >= enemies_per_wave and enemies.size() == 0:
		wave += 1
		enemies_spawned = 0
		enemies_per_wave = 8 + wave * 2
		spawn_interval = max(0.4, 1.2 - wave * 0.05)

	queue_redraw()

func _draw():
	# Background
	draw_rect(Rect2(0, 0, 800, 600), Color(0.04, 0.04, 0.1))

	if game_over:
		draw_string(ThemeDB.fallback_font, Vector2(300, 260), "SEGFAULT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 0.3, 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(280, 320),
			"Score: %d  Wave: %d" % [score, wave],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.8, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(260, 380),
			"Press ENTER/SPACE to retry",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
		return

	# HUD
	draw_string(ThemeDB.fallback_font, Vector2(20, 25),
		"SCORE: %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
	draw_string(ThemeDB.fallback_font, Vector2(350, 25),
		"WAVE: %d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.86, 0.79))
	var hearts = ""
	for i in range(lives):
		hearts += "♥ "
	draw_string(ThemeDB.fallback_font, Vector2(650, 25),
		hearts, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.4, 0.4))

	# Player
	draw_string(ThemeDB.fallback_font, Vector2(player_x - 15, 570),
		"(\\)", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.86, 0.79))
	draw_string(ThemeDB.fallback_font, Vector2(player_x - 42, 588),
		"ppx_sexp_conv", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.2, 0.4, 0.47))

	# Bullets
	for b in bullets:
		draw_rect(Rect2(b.x - 1, b.y, 3, 14), Color(0.5, 0.86, 0.79))

	# Enemies
	for e in enemies:
		if not e.has("render_x"):
			continue
		var hp_ratio = float(e.hp) / float(e.max_hp)
		var col = Color(0.78 * (1.0 - hp_ratio) + 0.78 * hp_ratio,
						0.55 * (1.0 - hp_ratio) + 0.57 * hp_ratio,
						0.42 * (1.0 - hp_ratio) + 0.92 * hp_ratio)
		draw_string(ThemeDB.fallback_font, Vector2(e.render_x - 50, e.y),
			e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		if e.max_hp > 1:
			var bx = e.render_x - 30
			draw_rect(Rect2(bx, e.y + 4, 60, 3), Color(0.1, 0.1, 0.18))
			draw_rect(Rect2(bx, e.y + 4, 60 * hp_ratio, 3),
				Color(0.5, 0.86, 0.79) if hp_ratio > 0.5 else Color(0.97, 0.55, 0.42))

	# Particles
	for p in particles:
		var alpha = clamp(p.life / 0.6, 0, 1)
		draw_string(ThemeDB.fallback_font, Vector2(p.x, p.y),
			p.char, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.5, 0.86, 0.79, alpha))

func restart():
	game_over = false
	score = 0
	wave = 1
	lives = 3
	bullets.clear()
	enemies.clear()
	particles.clear()
	enemies_spawned = 0
	enemies_per_wave = 8
	spawn_interval = 1.2
	player_x = 400.0
