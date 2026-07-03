extends Node

@onready var board: Board = $Board
@onready var game_logic: GameLogic = $GameLogic

func _ready():
	board.set_game_logic(game_logic)
