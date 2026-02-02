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

# Node references (we'll get these in _ready)
@onready var grid_container = $TetrisArea/GridContainer
@onready var score_label = $TetrisArea/ScoreLabel
@onready var lines_label = $TetrisArea/LinesLabel
@onready var damage_label = $TetrisArea/DamageLabel
@onready var enemy_health_bar = $BattleArea/Enemy/EnemyHealthBar
@onready var game_timer = $GameTimer
@onready var enemy_attack_timer = $EnemyAttackTimer
@onready var turn_timer = $TurnTimer
@onready var turn_timer_bar = $BattleArea/TurnTimerContainer/TurnTimerBar
@onready var turn_label = $BattleArea/TurnTimerContainer/TurnLabel

# These will hold the visual blocks we create
var grid_blocks = []  # 2D array of ColorRect nodes for placed blocks
var current_piece_visuals = []  # Array of ColorRect nodes for falling piece
var next_piece_visuals = []  # Array of ColorRect nodes for next piece preview


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
	
	# Initialize turn system
	start_player_turn()
	
	# Spawn the first piece
	next_piece_type = get_random_piece_type()
	spawn_new_piece()
	
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
	if game_over or not is_player_turn:
		return
	
	var new_pos = current_piece_position + direction
	if can_move_to(new_pos):
		current_piece_position = new_pos
		update_current_piece_visuals()


func rotate_piece():
	"""Rotates the current piece 90 degrees clockwise."""
	if game_over or not is_player_turn:
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
	"""Instantly drops the piece to the bottom."""
	if game_over or not is_player_turn:
		return
	
	while can_move_to(current_piece_position + Vector2(0, 1)):
		current_piece_position.y += 1
	
	lock_piece()


# ============================================
# PIECE LOCKING AND LINE CLEARING
# ============================================

func lock_piece():
	"""Locks the current piece into the grid and checks for line clears."""
	var color = PIECE_COLORS[current_piece_type]
	
	# Add each block to the grid
	for block_offset in current_piece_blocks:
		var pos = current_piece_position + block_offset
		if pos.y >= 0:  # Only if within grid
			grid[int(pos.y)][int(pos.x)] = color
	
	# Update grid visuals
	update_grid_visuals()
	
	# Check for completed lines
	var cleared = clear_completed_lines()
	
	if cleared > 0:
		# Calculate score and damage
		var points = calculate_score(cleared)
		var damage = calculate_damage(cleared)
		
		score += points
		lines_cleared += cleared
		total_damage += damage
		
		# Deal damage to enemy
		deal_damage_to_enemy(damage)
		
		# Visual feedback for line clear
		play_line_clear_effect()
	
	# Update UI
	update_ui()
	
	# Spawn next piece
	spawn_new_piece()


func clear_completed_lines() -> int:
	"""Checks for and clears completed lines. Returns number of lines cleared."""
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
	
	# Clear the lines
	for y in lines_to_clear:
		# Move all rows above down by one
		for row in range(y, 0, -1):
			for x in range(GRID_WIDTH):
				grid[row][x] = grid[row - 1][x]
		
		# Clear top row
		for x in range(GRID_WIDTH):
			grid[0][x] = null
	
	# Update visuals after clearing
	if lines_to_clear.size() > 0:
		update_grid_visuals()
	
	return lines_to_clear.size()


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
	"""Called when the enemy is defeated."""
	print("Enemy defeated!")
	# You could spawn a new enemy, show victory screen, etc.
	# For now, let's reset the enemy with more health
	enemy_max_health += 50
	enemy_health = enemy_max_health
	enemy_health_bar.max_value = enemy_max_health
	enemy_health_bar.value = enemy_health


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
	if game_over or is_paused or not is_player_turn:
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


func _input(event):
	"""Handles keyboard input (for testing on desktop)."""
	if game_over:
		return
	
	if event.is_action_pressed("ui_left"):
		move_piece(Vector2(-1, 0))
	elif event.is_action_pressed("ui_right"):
		move_piece(Vector2(1, 0))
	elif event.is_action_pressed("ui_up"):
		rotate_piece()
	elif event.is_action_pressed("ui_down"):
		move_piece(Vector2(0, 1))
	elif event.is_action_pressed("ui_accept"):  # Space or Enter
		hard_drop()
