import numpy as np
from dataclasses import dataclass, field


class Player:
    def __init__(self, id: int):
        self.id = id
        # Legg til stats som er unikt for spilleren


class Game:

    @dataclass
    class MoveInfo:
        """Mutable dataclass for move information"""
        is_winning_move: bool = False
        win_positions: list = field(default_factory=list)
        causes_opponent_to_win: bool = False
        opponent_win_positions: list = field(default_factory=list)
        is_missing_blocking_move: bool = False

    def __init__(self, p1: Player, p2: Player, p2_start=False, grid_size=4):
        self.grid_size = grid_size

        # z = 0 is the first plane
        #                         x          y          z
        self.grid = np.zeros((grid_size, grid_size, grid_size), dtype=int)

        self.directions = [ # 13 Unique directions to win
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
            (1, 1, 0), (1, 0, 1), (0, 1, 1), 
            (1, -1, 0), (1, 0, -1), (0, 1, -1), 
            (1, 1, 1), (1, -1, -1), (-1, 1, -1),
            (-1, -1, 1)
        ]
        self.actions = [(x, y) for x in range(self.grid_size) for y in range(self.grid_size)]

        self.p1 = p1
        self.p2 = p2
        self.current_player = self.p1
        if p2_start: self._switch_player()
    

    def reset_board(self, p2_start=False):
        """Empty grid and set P1 to start"""
        self.grid = np.zeros((self.grid_size, self.grid_size, self.grid_size), dtype=int)
        self.current_player = self.p2 if p2_start else self.p1 

    def request_move(self, action: tuple[int, int], player: Player) -> None:

        # Check if the move even makes sense
        if not self._is_move_possible(action, player): return

        position = self._action_to_position(action)

        move_info = self._get_move_info(position, player.id)


        # Check if the move request is valid
        if move_info.is_missing_blocking_move:
            print(f"You must block! {move_info.opponent_win_positions} is a winning positions for the opponent.")
            return
        elif move_info.causes_opponent_to_win:
            print("This move will cause the oponent to win! Choose another move.")
            return

        # Move is valid, make move
        self._set_id_at_position(position, player.id)

        if move_info.is_winning_move:
            print("WIN!")
            print(f"Winning positions: {move_info.win_positions}")
            # Stop game etc.
        else:
            # Continue game
            self._switch_player()

    
    def get_id_at_position(self, position: tuple[int, int, int]) -> int:
        return self.grid[position[0], position[1], position[2]]
    

    def print_game_board(self):
        print(f"Player: {self.current_player.id}'s turn.\n")
        for z in range(self.grid_size-1, -1, -1):
            print(self.grid[:,:,z])
            print("")
        

    # ----- Privates / Behind The Scenes Logic -----

    def _set_id_at_position(self, position: tuple[int, int, int], id: int) -> None:
        """Adds a piece to the position on the board"""
        self.grid[position[0], position[1], position[2]] = id


    def _get_move_info(self, position: tuple[int, int, int], player_id: int) -> MoveInfo:
        """Generic move checker. Returns a dict with info of the effects of the move"""
        
        move_info = Game.MoveInfo()

        # First, check if it is a winning move
        for direction in self.directions:
            connected_positions = self._get_connected_pieces(position, direction, player_id)
            if len(connected_positions) >= 4:
                move_info.is_winning_move = True
                move_info.win_positions = connected_positions
                return move_info

        # No win, check if the move needs to be a blocking move
        opponent_id = self._get_opponent_id(player_id)
        
        for action in self._get_possible_actions():
            pos = self._action_to_position(action)

            opponent_wins = self._is_winning_position(pos, opponent_id)

            if opponent_wins:
                move_info.opponent_win_positions.append(pos)

        must_block = len(move_info.opponent_win_positions) > 0
        if must_block:
            if position in move_info.opponent_win_positions:
                # Blocked correctly
                return move_info
            else:
                # Move is not valid
                move_info.is_missing_blocking_move = True
                return move_info
    

        # Lastly, check if the the move causes the opponent to win if placed on top
        # This is invalid if there are other moves that does not cause the opponent to win

        spot_above = lambda pos: (pos[0], pos[1], pos[2]+1) if pos[2] < self.grid_size-1 else None

        if spot_above(position) is None: return move_info

        # Check if there are other moves that does not cause the opponent to win
        for action in self.actions:
            pos = self._action_to_position(action)

            if spot_above(pos) is None: continue

            if self._is_winning_position(spot_above(pos), opponent_id):
                move_info.causes_opponent_to_win = True
                return move_info


        return move_info
    
    def _is_winning_position(self, position: tuple[int, int, int], player_id: int) -> bool:
        """Returns True if the position is a winning position for the player id"""
        for direction in self.directions:
            connected_positions = self._get_connected_pieces(position, direction, player_id)
            if len(connected_positions) >= 4:
                return True
        return False
            
    def _get_possible_actions(self) -> list[tuple[int, int]]:
        """Returns a list of possible actions"""
        possible_actions = []
        for action in self.actions:
            if self._is_move_possible(action):
                possible_actions.append(action)
        return possible_actions

        
    def _get_connected_pieces(self, 
                            position: tuple[int, int, int], 
                            direction: tuple[int, int, int], 
                            player_id: int,
                            count_initial_pos=True # Check what would happen
                        ) -> list[tuple[int, int, int]]:
        """
        Returns a list of positions of connected pieces of selected id.
        """
        dx, dy, dz = direction
        connection: list[tuple[int, int, int]] = []
        
        # Add start position
        if count_initial_pos: connection.append(position)

        # Go in positive direction, excluding current spot
        px, py, pz = position
        for _ in range(self.grid_size):
            px += dx
            py += dy
            pz += dz
            current_pos = (px, py, pz)
            if not self._is_inside_grid(current_pos) or self.get_id_at_position(current_pos) != player_id: break
            connection.append(current_pos)

        # Go in negative direction, excluding current spot
        px, py, pz = position
        for _ in range(self.grid_size):
            px -= dx
            py -= dy
            pz -= dz
            current_pos = (px, py, pz)
            if not self._is_inside_grid(current_pos) or self.get_id_at_position(current_pos) != player_id: break
            connection.append(current_pos)
        
        return connection
    
    def _is_move_possible(self, action: tuple[int, int], player: Player | None = None) -> bool:
        """Check if the move makes sense physically. Optionally checks players turn."""
        
        x, y = action
    
        # Is players turn?
        if player is not None:
            if player is not self.current_player: 
                print(f"Player {self.current_player.id}s turn.")
                return False
        
        # Inside grid?
        if not action in self.actions: 
            print(f"Action {x, y} is out of bounds")
            return False

        # Free spot?
        if self.grid[x, y, self.grid_size-1] != 0: 
            print(f"Cannot build higher than {self.grid_size}")
            return False

        return True
    
    def _is_inside_grid(self, position: tuple[int, int, int]) -> bool:
        return 0 <= position[0] < self.grid_size and 0 <= position[1] < self.grid_size and 0 <= position[2] < self.grid_size

    def _action_to_position(self, action: tuple[int, int]) -> tuple[int, int, int]:
        """Assumes the action is possible"""
        x, y = action
        z = self._get_z(action)
        return (x, y, z)

    def _get_z(self, action: tuple[int, int]) -> int:
        """Returns first available free spot in z"""
        x, y = action
        col = self.grid[x, y]
        z = 0
        for spot in col:
            if spot == 0:
                break
            z += 1
        return z
    
    def _switch_player(self):
        if self.current_player == self.p1: self.current_player = self.p2
        else: self.current_player = self.p1

    def _get_opponent_id(self, player_id):
        return self.p1.id if player_id != self.p1.id else self.p2.id
