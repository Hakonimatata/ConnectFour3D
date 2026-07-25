
from environment.game import Game


class GameManager:
    def __init__(self):
        
        
        self.active_games = []


        
        pass


    def create_new_game(self):

        # Select rules

        
        game = Game()
        game.finished.connect(self._on_game_ended)

        self.active_games.append(game)
        

    def _on_game_ended(self):
        pass