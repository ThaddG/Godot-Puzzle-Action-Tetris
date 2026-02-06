extends Node2D

# ============================================
# TETRIS BATTLE GAME - MAIN SCRIPT
# ============================================
# This script controls the entire game:
# - Tetris grid and piece movement
# - Battle system (damaging enemy when clearing lines)
# - Touch controls for mobile
# ============================================

# --- CONSTANTS (values that never change) ---

# Grid dimensions (standard Tetris is 10 wide, 20 tall)
const GRID_WIDTH = 10
const GRID_HEIGHT = 20
const CELL_SIZE = 30  # Each cell is 30x30 pixels

# All 7 Tetris pieces (called Tetrominoes)
# Each piece is defined by 4 block positions relative to center
const TETROMINOS = {
	"I": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)],
	"O": [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)],
	"T": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
	"S": [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1)],
	"Z": [Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
	"J": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	"L": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(-1, 1)]
}

# Colors for each piece type
const PIECE_COLORS = {
	"I": Color(0, 1, 1),      # Cyan
	"O": Color(1, 1, 0),      # Yellow
	"T": Color(0.6, 0, 1),    # Purple
	"S": Color(0, 1, 0),      # Green
	"Z": Color(1, 0, 0),      # Red
	"J": Color(0, 0, 1),      # Blue
	"L": Color(1, 0.5, 0)     # Orange
}

# --- GAME STATE VARIABLES ---

# The grid stores what's in each cell (null = empty, or a color)
var grid = []

# Current falling piece info
var current_piece_type = ""
var current_piece_blocks = []  # Array of Vector2 positions
var current_piece_position = Vector2(4, 0)  # Starting position (top-middle)

# Next piece (shown in preview box)
var next_piece_type = ""

# Game statistics
var score = 0
var lines_cleared = 0
var total_damage = 0

# Combo system (for gravity chain reactions)
var current_combo = 0  # Current chain count (resets when no more clears)
var combo_multiplier = 1  # Damage multiplier based on combo
var is_chain_active = false  # True while processing gravity chains

# Battle system
var enemy_health = 100
var enemy_max_health = 100
var player_health = 100

# Turn-based system
var is_player_turn = true
var turn_time_remaining = 30.0  # 30 seconds per turn
const TURN_DURATION = 30.0  # Constant for turn length
var enemy_attack_phase = false  # True when enemy is attacking

# Game state
var game_over = false
var is_paused = false
var is_locking_piece = false  # Prevents race condition during async lock_piece

# Soft drop (hold to fast drop)
var is_soft_dropping = false  # True when player is holding down
const SOFT_DROP_SPEED = 0.05  # How fast pieces fall when holding (very fast!)
const NORMAL_DROP_SPEED = 0.5  # Normal fall speed

# Node references (we'll get these in _ready)
@onready var grid_container = $TetrisArea/GridContainer
@onready var score_label = $TetrisArea/ScoreLabel
@onready var lines_label = $TetrisArea/LinesLabel
@onready var damage_label = $TetrisArea/DamageLabel
@onready var combo_label = $TetrisArea/ComboLabel
@onready var combo_multiplier_label = $TetrisArea/ComboContainer/ComboMultiplier
@onready var enemy_health_bar = $BattleArea/Enemy/EnemyHealthBar
@onready var game_timer = $GameTimer
@onready var enemy_attack_timer = $EnemyAttackTimer
@onready var turn_timer = $TurnTimer
@onready var turn_timer_bar = $BattleArea/TurnTimerContainer/TurnTimerBar
@onready var turn_label = $BattleArea/TurnTimerContainer/TurnLabel
@onready var fast_drop_timer = $FastDropTimer
@onready var pause_overlay = $UI/PauseOverlay

# These will hold the visual blocks we create
var grid_blocks = []  # 2D array of ColorRect nodes for placed blocks
var current_piece_visuals = []  # Array of ColorRect nodes for falling piece
var next_piece_visuals = []  # Array of ColorRect nodes for next piece preview
var ghost_piece_visuals = []  # Array of ColorRect nodes for ghost/shadow piece


# ============================================
# INITIALIZATION
# ============================================

func _ready():
	"""Called when the scene loads. Sets up the entire game."""
	print("Game starting!")
	
	# Initialize the grid as a 2D array filled with null (empty)
	initialize_grid()
	
	# Create visual blocks for the grid
	create_grid_visuals()
	
	# Connect button signals (when buttons are pressed, call functions)
	connect_buttons()
	
	# Connect timer signals
	game_timer.timeout.connect(_on_game_timer_timeout)
	enemy_attack_timer.timeout.connect(_on_enemy_attack_timer_timeout)
	turn_timer.timeout.connect(_on_turn_timer_timeout)
	fast_drop_timer.timeout.connect(_on_fast_drop_timer_timeout)
	
	# Initialize turn system
	start_player_turn()
	
	# Spawn the first piece
	# We need TWO pieces ready: one to spawn now, one to show in preview
	var first_piece = get_random_piece_type()
	next_piece_type = get_random_piece_type()  # This will show in preview
	
	# Manually set up the first piece (don't use spawn_new_piece which would regenerate next)
	current_piece_type = first_piece
	current_piece_blocks = TETROMINOS[current_piece_type].duplicate()
	current_piece_position = Vector2(4, 0)
	update_current_piece_visuals()
	update_next_piece_preview()
	
	# Update the UI
	update_ui()


func initialize_grid():
	"""Creates an empty grid (2D array of nulls)."""
	grid = []
	for y in range(GRID_HEIGHT):
		var row = []
		for x in range(GRID_WIDTH):
			row.append(null)  # null means empty
		grid.append(row)


func create_grid_visuals():
	"""Creates ColorRect nodes for each grid cell (for displaying placed blocks)."""
	grid_blocks = []
	for y in range(GRID_HEIGHT):
		var row = []
		for x in range(GRID_WIDTH):
			var block = ColorRect.new()
			block.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)  # Slightly smaller for gap
			block.position = Vector2(x * CELL_SIZE + 1, y * CELL_SIZE + 1)
			block.color = Color(0, 0, 0, 0)  # Transparent (invisible when empty)
			grid_container.add_child(block)
			row.append(block)
		grid_blocks.append(row)


func connect_buttons():
	"""Connects the touch control buttons to their functions."""
	$UI/TouchControls/LeftButton.pressed.connect(_on_left_pressed)
	$UI/TouchControls/RightButton.pressed.connect(_on_right_pressed)
	$UI/TouchControls/RotateButton.pressed.connect(_on_rotate_pressed)
	$UI/TouchControls/DropButton.pressed.connect(_on_drop_pressed)
	
	# Soft drop button - detect press AND release
	var soft_drop_btn = $UI/TouchControls/SoftDropButton
	soft_drop_btn.button_down.connect(_on_soft_drop_pressed)
	soft_drop_btn.button_up.connect(_on_soft_drop_released)
	
	# Pause buttons
	$UI/TouchControls/PauseButton.pressed.connect(toggle_pause)
	$UI/PauseOverlay/ResumeButton.pressed.connect(toggle_pause)


# ============================================
# PIECE SPAWNING
# ============================================

func get_random_piece_type() -> String:
	"""Returns a random piece type (I, O, T, S, Z, J, or L)."""
	var types = TETROMINOS.keys()  # Get all piece names
	return types[randi() % types.size()]  # Pick random one


func spawn_new_piece():
	"""Creates a new falling piece at the top of the grid."""
	# The "next" piece becomes the current piece
	current_piece_type = next_piece_type
	# Generate a new "next" piece
	next_piece_type = get_random_piece_type()
	
	# Copy the piece shape (we copy so we can rotate without affecting original)
	current_piece_blocks = TETROMINOS[current_piece_type].duplicate()
	
	# Start at top-center of grid
	current_piece_position = Vector2(4, 0)
	
	# Check if the spawn position is blocked (game over condition)
	if not can_move_to(current_piece_position):
		game_over = true
		print("GAME OVER!")
		game_timer.stop()
		return
	
	# Create visual representation of the piece
	update_current_piece_visuals()
	update_next_piece_preview()


func update_current_piece_visuals():
	"""Updates the visual display of the current falling piece."""
	# Remove old visuals
	for block in current_piece_visuals:
		block.queue_free()
	current_piece_visuals.clear()

	# Create new visuals for each block in the piece
	var color = PIECE_COLORS[current_piece_type]
	for block_offset in current_piece_blocks:
		var block = ColorRect.new()
		block.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
		var pos = current_piece_position + block_offset
		block.position = Vector2(pos.x * CELL_SIZE + 1, pos.y * CELL_SIZE + 1)
		block.color = color
		grid_container.add_child(block)
		current_piece_visuals.append(block)

	# Also update the ghost piece
	update_ghost_piece()


func update_next_piece_preview():
	"""Updates the "next piece" preview box."""
	# Remove old preview
	for block in next_piece_visuals:
		block.queue_free()
	next_piece_visuals.clear()

	# Get the next piece container
	var preview_box = $TetrisArea/NextPieceBox

	# Create blocks for preview
	var color = PIECE_COLORS[next_piece_type]
	var blocks = TETROMINOS[next_piece_type]

	for block_offset in blocks:
		var block = ColorRect.new()
		block.size = Vector2(25, 25)  # Smaller for preview
		# Center the piece in the preview box
		block.position = Vector2(60 + block_offset.x * 27, 60 + block_offset.y * 27)
		block.color = color
		preview_box.add_child(block)
		next_piece_visuals.append(block)


func update_ghost_piece():
	"""Updates the ghost/shadow piece showing where the current piece will land."""
	# Remove old ghost visuals
	for block in ghost_piece_visuals:
		block.queue_free()
	ghost_piece_visuals.clear()

	# Skip if ghost piece is disabled in settings
	var settings = get_node_or_null("/root/GameSettings")
	if settings and not settings.ghost_piece_enabled:
		return

	# Calculate ghost position (drop straight down until collision)
	var ghost_y = current_piece_position.y
	while can_move_to(Vector2(current_piece_position.x, ghost_y + 1)):
		ghost_y += 1

	# Don't show ghost if piece is already at landing position
	if ghost_y == current_piece_position.y:
		return

	# Create ghost visuals (semi-transparent version of current piece)
	var color = PIECE_COLORS[current_piece_type]
	color.a = 0.3  # Make it semi-transparent

	for block_offset in current_piece_blocks:
		var block = ColorRect.new()
		block.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
		var pos = Vector2(current_piece_position.x, ghost_y) + block_offset
		block.position = Vector2(pos.x * CELL_SIZE + 1, pos.y * CELL_SIZE + 1)
		block.color = color
		grid_container.add_child(block)
		ghost_piece_visuals.append(block)


# ============================================
# MOVEMENT AND COLLISION
# ============================================

func can_move_to(new_position: Vector2) -> bool:
	"""Checks if the piece can move to a new position without collision."""
	for block_offset in current_piece_blocks:
		var check_pos = new_position + block_offset
		
		# Check boundaries
		if check_pos.x < 0 or check_pos.x >= GRID_WIDTH:
			return false  # Out of bounds horizontally
		if check_pos.y >= GRID_HEIGHT:
			return false  # Below the grid
		if check_pos.y < 0:
			continue  # Above grid is okay (for spawning)
		
		# Check collision with placed blocks
		if grid[int(check_pos.y)][int(check_pos.x)] != null:
			return false  # Collision with existing block
	
	return true  # No collision, move is valid


func move_piece(direction: Vector2):
	"""Attempts to move the piece in a direction."""
	if game_over or not is_player_turn or is_locking_piece:
		return
	
	var new_pos = current_piece_position + direction
	if can_move_to(new_pos):
		current_piece_position = new_pos
		update_current_piece_visuals()


func rotate_piece():
	"""Rotates the current piece 90 degrees clockwise."""
	if game_over or not is_player_turn or is_locking_piece:
		return
	
	# O piece doesn't rotate
	if current_piece_type == "O":
		return
	
	# Calculate rotated positions (90 degrees clockwise: (x,y) -> (y,-x))
	var rotated_blocks = []
	for block in current_piece_blocks:
		rotated_blocks.append(Vector2(block.y, -block.x))
	
	# Temporarily save old blocks and try rotation
	var old_blocks = current_piece_blocks.duplicate()
	current_piece_blocks = rotated_blocks
	
	# Check if rotation is valid
	if can_move_to(current_piece_position):
		update_current_piece_visuals()
	else:
		# Try wall kicks (shifting piece if rotation hits wall)
		var kicks = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(-2, 0), Vector2(2, 0)]
		var kicked = false
		for kick in kicks:
			if can_move_to(current_piece_position + kick):
				current_piece_position += kick
				update_current_piece_visuals()
				kicked = true
				break
		
		if not kicked:
			# Rotation failed, restore old blocks
			current_piece_blocks = old_blocks


func hard_drop():
	"""Drops the piece to the bottom with a quick slide animation."""
	if game_over or not is_player_turn or is_locking_piece:
		return
	
	# Calculate the final position
	var final_y = current_piece_position.y
	while can_move_to(Vector2(current_piece_position.x, final_y + 1)):
		final_y += 1
	
	# If already at bottom, just lock
	if final_y == current_piece_position.y:
		lock_piece()
		return
	
	# Animate the drop with a quick slide
	is_locking_piece = true  # Prevent input during animation
	var drop_distance = final_y - current_piece_position.y
	var drop_time = min(0.08, drop_distance * 0.008)  # Faster slide, max 0.08 seconds
	
	# Animate each block sliding down
	var start_y = current_piece_position.y
	var tween = create_tween()
	tween.tween_method(
		func(y): 
			current_piece_position.y = y
			update_current_piece_visuals(),
		start_y,
		final_y,
		drop_time
	)
	
	# Wait for animation to complete, then lock
	await tween.finished
	is_locking_piece = false
	lock_piece()


# ============================================
# PIECE LOCKING AND LINE CLEARING
# ============================================

func lock_piece():
	"""Locks the current piece into the grid and starts the chain reaction."""
	# Prevent multiple calls while async operations are running
	if is_locking_piece:
		return
	is_locking_piece = true

	# IMMEDIATELY clear the falling piece visuals so they don't ghost
	for block in current_piece_visuals:
		block.queue_free()
	current_piece_visuals.clear()

	# Also clear ghost piece visuals
	for block in ghost_piece_visuals:
		block.queue_free()
	ghost_piece_visuals.clear()
	
	var color = PIECE_COLORS[current_piece_type]
	
	# Add each block to the grid
	for block_offset in current_piece_blocks:
		var pos = current_piece_position + block_offset
		if pos.y >= 0:  # Only if within grid
			grid[int(pos.y)][int(pos.x)] = color
	
	# Update grid visuals
	update_grid_visuals()
	
	# Start the chain reaction process
	# Reset combo at the start of each piece placement
	current_combo = 0
	combo_multiplier = 1
	is_chain_active = true
	
	# Process chains (this will keep going until no more lines clear)
	await process_gravity_chain()
	
	# Chain is done
	is_chain_active = false
	
	# Hide combo display after chain ends
	await get_tree().create_timer(0.5).timeout
	if current_combo == 0 or not is_chain_active:
		combo_label.text = ""
		combo_multiplier_label.text = ""
	
	# Update UI
	update_ui()
	
	# Spawn next piece
	spawn_new_piece()
	
	# Allow lock_piece to be called again
	is_locking_piece = false


func process_gravity_chain():
	"""Processes gravity and line clears in a chain until no more clears happen."""
	var chain_continues = true
	
	while chain_continues:
		# First, check for and clear completed lines
		var cleared = find_and_clear_lines()
		
		if cleared > 0:
			# Increment combo
			current_combo += 1
			combo_multiplier = int(pow(2, current_combo - 1))  # x1, x2, x4, x8, x16...
			
			# Update combo display
			update_combo_display(cleared)
			
			# Calculate score and damage with combo multiplier
			var base_points = calculate_score(cleared)
			var base_damage = calculate_damage(cleared)
			
			var combo_points = base_points * combo_multiplier
			var combo_damage = base_damage * combo_multiplier
			
			score += combo_points
			lines_cleared += cleared
			total_damage += combo_damage
			
			# Deal damage to enemy
			deal_damage_to_enemy(combo_damage)
			
			# Visual feedback
			play_line_clear_effect()
			if current_combo > 1:
				play_combo_effect()
			
			# Update UI during chain
			update_ui()
			
			# Wait a moment for visual effect
			await get_tree().create_timer(0.3).timeout
			
			# Apply gravity - blocks fall into empty spaces
			var blocks_fell = apply_gravity()
			
			if blocks_fell:
				# Wait for gravity animation
				await get_tree().create_timer(0.2).timeout
				# Continue the loop to check for new line clears
				chain_continues = true
			else:
				# No blocks fell, chain ends
				chain_continues = false
		else:
			# No lines cleared, chain ends
			chain_continues = false


func find_and_clear_lines() -> int:
	"""Finds completed lines, clears them (without shifting), returns count."""
	var lines_to_clear = []
	
	# Check each row from bottom to top
	for y in range(GRID_HEIGHT - 1, -1, -1):
		var is_complete = true
		for x in range(GRID_WIDTH):
			if grid[y][x] == null:
				is_complete = false
				break
		
		if is_complete:
			lines_to_clear.append(y)
	
	# Clear the lines (set to null, don't shift yet - gravity will handle that)
	for y in lines_to_clear:
		for x in range(GRID_WIDTH):
			grid[y][x] = null
	
	# Update visuals after clearing
	if lines_to_clear.size() > 0:
		update_grid_visuals()
	
	return lines_to_clear.size()


func apply_gravity() -> bool:
	"""Makes all floating blocks fall down. Returns true if any blocks moved."""
	var blocks_moved = false
	
	# Process from bottom to top, for each column
	for x in range(GRID_WIDTH):
		# Find the lowest empty spot and drop blocks into it
		var write_y = GRID_HEIGHT - 1  # Start at bottom
		
		# Go from bottom to top
		for read_y in range(GRID_HEIGHT - 1, -1, -1):
			if grid[read_y][x] != null:
				# There's a block here
				if read_y != write_y:
					# Move it down to the write position
					grid[write_y][x] = grid[read_y][x]
					grid[read_y][x] = null
					blocks_moved = true
				write_y -= 1  # Move write position up
	
	# Update visuals after gravity
	if blocks_moved:
		update_grid_visuals()
	
	return blocks_moved


func update_combo_display(lines: int):
	"""Updates the combo display during a chain."""
	if current_combo == 1:
		combo_label.text = str(lines) + " LINE" + ("S" if lines > 1 else "") + "!"
		combo_multiplier_label.text = ""
	else:
		combo_label.text = "CHAIN x" + str(current_combo) + "!"
		combo_multiplier_label.text = "x" + str(combo_multiplier)
		
		# Make combo text pulse with color based on combo level
		var combo_color = Color(1, 1, 1)  # White default
		if current_combo >= 5:
			combo_color = Color(1, 0, 1)  # Magenta for huge combos
		elif current_combo >= 4:
			combo_color = Color(1, 0, 0)  # Red
		elif current_combo >= 3:
			combo_color = Color(1, 0.5, 0)  # Orange
		elif current_combo >= 2:
			combo_color = Color(1, 1, 0)  # Yellow
		
		combo_label.modulate = combo_color


func play_combo_effect():
	"""Visual effect for combos."""
	# Scale up the combo label
	var tween = create_tween()
	combo_multiplier_label.scale = Vector2(1.5, 1.5)
	tween.tween_property(combo_multiplier_label, "scale", Vector2(1, 1), 0.2)
	
	# Flash the grid with combo color
	var grid_bg = $TetrisArea/GridContainer/GridBackground
	var flash_tween = create_tween()
	var flash_color = Color(0.5, 0.3, 0.1) if current_combo >= 3 else Color(0.3, 0.3, 0.1)
	flash_tween.tween_property(grid_bg, "color", flash_color, 0.1)
	flash_tween.tween_property(grid_bg, "color", Color(0.02, 0.02, 0.05), 0.1)


# NOTE: clear_completed_lines has been replaced by find_and_clear_lines + apply_gravity
# The new gravity system handles line clearing with chain combos


func update_grid_visuals():
	"""Updates the visual display of the entire grid."""
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if grid[y][x] != null:
				grid_blocks[y][x].color = grid[y][x]
			else:
				grid_blocks[y][x].color = Color(0, 0, 0, 0)  # Transparent


# ============================================
# SCORING AND DAMAGE SYSTEM
# ============================================

func calculate_score(lines: int) -> int:
	"""Calculates score based on lines cleared (Tetris scoring)."""
	match lines:
		1: return 100
		2: return 300
		3: return 500
		4: return 800  # Tetris!
		_: return 0


func calculate_damage(lines: int) -> int:
	"""Calculates damage based on lines cleared."""
	match lines:
		1: return 10
		2: return 25
		3: return 40
		4: return 80  # Tetris does massive damage!
		_: return 0


func deal_damage_to_enemy(damage: int):
	"""Deals damage to the enemy and triggers attack animation."""
	enemy_health = max(0, enemy_health - damage)
	enemy_health_bar.value = enemy_health
	
	# Trigger player attack animation
	play_attack_animation()
	
	# Check for enemy defeat
	if enemy_health <= 0:
		enemy_defeated()


func enemy_defeated():
	"""Called when the enemy is defeated - VICTORY!"""
	game_over = true
	print("VICTORY! Enemy defeated!")
	
	# Stop all timers
	game_timer.stop()
	turn_timer.stop()
	fast_drop_timer.stop()
	
	# Update turn label to show victory
	turn_label.text = "VICTORY!"
	turn_timer_bar.value = turn_timer_bar.max_value
	turn_timer_bar.modulate = Color(1, 0.84, 0)  # Gold color
	
	# Victory animation - flash enemy red then fade out
	var enemy_rect = $BattleArea/Enemy/EnemyPlaceholder
	var tween = create_tween()
	tween.tween_property(enemy_rect, "color", Color(1, 1, 1), 0.1)
	tween.tween_property(enemy_rect, "color", Color(0.5, 0, 0), 0.2)
	tween.tween_property(enemy_rect, "modulate:a", 0.0, 0.5)  # Fade out


# ============================================
# BATTLE ANIMATIONS
# ============================================

func play_attack_animation():
	"""Plays a simple attack animation (player moves toward enemy)."""
	var player = $BattleArea/Player
	var original_pos = player.position
	
	# Create a simple tween animation
	var tween = create_tween()
	tween.tween_property(player, "position", Vector2(350, 200), 0.15)
	tween.tween_property(player, "position", original_pos, 0.15)


func play_enemy_attack_animation():
	"""Plays enemy attack animation."""
	var enemy = $BattleArea/Enemy
	var original_pos = enemy.position
	
	var tween = create_tween()
	tween.tween_property(enemy, "position", Vector2(300, 250), 0.2)
	tween.tween_property(enemy, "position", original_pos, 0.2)


func play_line_clear_effect():
	"""Visual effect when lines are cleared."""
	# Flash the grid
	var tween = create_tween()
	var grid_bg = $TetrisArea/GridContainer/GridBackground
	tween.tween_property(grid_bg, "color", Color(0.3, 0.3, 0.4), 0.1)
	tween.tween_property(grid_bg, "color", Color(0.02, 0.02, 0.05), 0.1)


# ============================================
# UI UPDATES
# ============================================

func update_ui():
	"""Updates all UI elements."""
	score_label.text = "SCORE: " + str(score)
	lines_label.text = "LINES: " + str(lines_cleared)
	damage_label.text = "DAMAGE: " + str(total_damage)


# ============================================
# TIMER CALLBACKS
# ============================================

func _on_game_timer_timeout():
	"""Called every tick - moves piece down automatically."""
	if game_over or is_paused or not is_player_turn or is_locking_piece:
		return
	
	# Try to move down
	if can_move_to(current_piece_position + Vector2(0, 1)):
		current_piece_position.y += 1
		update_current_piece_visuals()
	else:
		# Can't move down - lock the piece
		lock_piece()


func _on_enemy_attack_timer_timeout():
	"""Enemy attacks when their turn comes."""
	if game_over:
		return
	
	# Enemy deals damage to player
	var enemy_damage = randi_range(5, 15)
	player_health = max(0, player_health - enemy_damage)
	
	play_enemy_attack_animation()
	
	# Flash player to show damage
	var player_rect = $BattleArea/Player/PlayerPlaceholder
	var tween = create_tween()
	tween.tween_property(player_rect, "color", Color(1, 0, 0), 0.1)
	tween.tween_property(player_rect, "color", Color(0.2, 0.6, 1), 0.1)
	
	print("Enemy dealt " + str(enemy_damage) + " damage! Player health: " + str(player_health))
	
	if player_health <= 0:
		game_over = true
		print("Player defeated! GAME OVER!")
		game_timer.stop()
		turn_timer.stop()
	else:
		# After enemy attacks, give turn back to player
		start_player_turn()


func _on_turn_timer_timeout():
	"""Called every second to update the turn timer."""
	if game_over or not is_player_turn:
		return
	
	# Decrease time remaining
	turn_time_remaining -= 1.0
	
	# Update the visual timer bar
	update_turn_timer_display()
	
	# Check if turn is over
	if turn_time_remaining <= 0:
		end_player_turn()


func start_player_turn():
	"""Starts the player's turn with full time."""
	is_player_turn = true
	enemy_attack_phase = false
	turn_time_remaining = TURN_DURATION
	
	# Update display
	update_turn_timer_display()
	
	# Make sure timers are running correctly
	game_timer.start()  # Tetris pieces fall
	turn_timer.start()  # Turn countdown
	
	print("Player turn started! You have " + str(TURN_DURATION) + " seconds.")


func end_player_turn():
	"""Ends the player's turn and triggers enemy attack."""
	is_player_turn = false
	enemy_attack_phase = true
	
	# Update display to show enemy turn
	turn_label.text = "ENEMY TURN!"
	turn_timer_bar.value = 0
	
	# Change bar color to red during enemy turn
	turn_timer_bar.modulate = Color(1, 0.3, 0.3)
	
	# Pause the Tetris game during enemy attack
	game_timer.stop()
	turn_timer.stop()
	
	print("Player turn ended! Enemy is attacking...")
	
	# Delay before enemy attacks (for dramatic effect)
	await get_tree().create_timer(0.5).timeout
	
	# Trigger enemy attack
	_on_enemy_attack_timer_timeout()


func update_turn_timer_display():
	"""Updates the turn timer bar and label."""
	turn_timer_bar.value = turn_time_remaining
	turn_label.text = "YOUR TURN - " + str(int(turn_time_remaining)) + "s"
	
	# Change color based on time remaining
	if turn_time_remaining > 20:
		turn_timer_bar.modulate = Color(0.3, 1, 0.3)  # Green - plenty of time
	elif turn_time_remaining > 10:
		turn_timer_bar.modulate = Color(1, 1, 0.3)  # Yellow - getting low
	else:
		turn_timer_bar.modulate = Color(1, 0.3, 0.3)  # Red - urgent!


# ============================================
# INPUT HANDLING
# ============================================

func _on_left_pressed():
	"""Move piece left."""
	move_piece(Vector2(-1, 0))


func _on_right_pressed():
	"""Move piece right."""
	move_piece(Vector2(1, 0))


func _on_rotate_pressed():
	"""Rotate piece."""
	rotate_piece()


func _on_drop_pressed():
	"""Hard drop piece."""
	hard_drop()


func _on_soft_drop_pressed():
	"""Called when soft drop button is pressed down."""
	if game_over or not is_player_turn or is_locking_piece:
		return
	is_soft_dropping = true
	fast_drop_timer.start()
	# Also move down immediately
	soft_drop_step()


func _on_soft_drop_released():
	"""Called when soft drop button is released."""
	is_soft_dropping = false
	fast_drop_timer.stop()


func _on_fast_drop_timer_timeout():
	"""Called rapidly while holding soft drop - moves piece down fast."""
	if is_soft_dropping and is_player_turn and not game_over and not is_locking_piece:
		soft_drop_step()


func soft_drop_step():
	"""Move the piece down one step during soft drop."""
	if can_move_to(current_piece_position + Vector2(0, 1)):
		current_piece_position.y += 1
		update_current_piece_visuals()
	else:
		# Hit bottom, lock the piece
		is_soft_dropping = false
		fast_drop_timer.stop()
		lock_piece()


func _input(event):
	"""Handles keyboard input (for testing on desktop)."""
	# Pause can be toggled even during game over to dismiss
	if event.is_action_pressed("ui_cancel"):  # Escape key
		toggle_pause()
		return
	
	if game_over or is_paused:
		return
	
	if event.is_action_pressed("ui_left"):
		move_piece(Vector2(-1, 0))
	elif event.is_action_pressed("ui_right"):
		move_piece(Vector2(1, 0))
	elif event.is_action_pressed("ui_up"):
		rotate_piece()
	elif event.is_action_pressed("ui_down"):
		# Start soft drop when down is pressed
		_on_soft_drop_pressed()
	elif event.is_action_released("ui_down"):
		# Stop soft drop when down is released
		_on_soft_drop_released()
	elif event.is_action_pressed("ui_accept"):  # Space or Enter
		hard_drop()


func toggle_pause():
	"""Toggles the pause state of the game."""
	if game_over:
		return
	
	is_paused = !is_paused
	
	if is_paused:
		# Pause the game
		game_timer.paused = true
		turn_timer.paused = true
		fast_drop_timer.stop()
		is_soft_dropping = false
		
		# Show pause overlay
		pause_overlay.visible = true
		
		print("Game paused")
	else:
		# Resume the game
		game_timer.paused = false
		turn_timer.paused = false
		
		# Hide pause overlay
		pause_overlay.visible = false
		
		print("Game resumed")
