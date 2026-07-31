import numpy as np
from dataclasses import dataclass, field
from enum import Enum, auto
from .signals import Signal


class MoveReason(Enum):
    OK = auto()
    WIN = auto()
    NOT_YOUR_TURN = auto()
    OUT_OF_BOUNDS = auto()
    MUST_BLOCK = auto()
    GIVES_OPPONENT_WIN = auto()
    INVALID_REQUEST = auto()


class Piece(Enum):
    EMPTY = 0
    P1 = 1
    P2 = 2


@dataclass(frozen=True)
class MoveResult:
    valid: bool
    reason: MoveReason


@dataclass
class GameRules:
    """Rules for the game"""
    must_block: bool = False
    must_not_give_victory: bool = False



class GameState(Enum):
    NOT_STARTED = auto()
    WIN = auto()
    DRAW = auto()
    PLAYING = auto()
    PAUSED = auto()



class Game:

    def __init__(self, p1_id: int, p2_id: int, rules: 
                 GameRules, grid_size=4):
        
        if p1_id == p2_id:
            raise ValueError("Player IDs must be different.")
        
        
        self._grid_size = grid_size

        # z = 0 is the first plane
        #                         x          y          z
        self._grid = np.zeros((grid_size, grid_size, grid_size), dtype=int)
        self._actions = [(x, y) for x in range(self._grid_size) for y in range(self._grid_size)]

        self.DIRECTIONS = [ # 13 Unique directions
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
            (1, 1, 0), (1, 0, 1), (0, 1, 1), 
            (1, -1, 0), (1, 0, -1), (0, 1, -1), 
            (1, 1, 1), (1, -1, -1), (-1, 1, -1),
            (-1, -1, 1)
        ]

        self._player_ids = {
            Piece.P1: p1_id,
            Piece.P2: p2_id,
        }
        self._current_piece = Piece.P1
        
        self._rules = rules
        self._game_state = GameState.NOT_STARTED

        # SIGNALS
        self.finished: Signal = Signal()

        self.pos_to_valid_directions: dict[tuple[int, int, int], list[tuple[int, int, int]]] = {} # Lenker posisjon til gyldige retninger
        self._setup_valid_directions()

    def _setup_valid_directions(self) -> None:
        for x in range(self._grid_size):
            for y in range(self._grid_size):
                for z in range(self._grid_size):
                    position = (x, y, z)
                    valid_directions_list = []

                    for direction in self.DIRECTIONS:
                        if self.is_valid_direction(position, direction):
                            valid_directions_list.append(direction)

                    self.pos_to_valid_directions[position] = valid_directions_list


    def start_game(self):
        """ Starts game after initial setup in __init__ is done """
        self._game_state = GameState.PLAYING
    

    def request_move(self, action: tuple[int, int], player_id: int) -> MoveResult:
        """Request move from player, react, and return result of move"""

        piece: Piece = self._player_id_to_piece(player_id)

        if self._game_state != GameState.PLAYING:
            return MoveResult(valid=False, reason=MoveReason.INVALID_REQUEST)
        
        result = self._get_move_result(action, piece)
        
        if result.valid:
            
            # Make move
            position = self.action_to_position(action)
            self._set_piece_at_position(position, piece)

            if result.reason == MoveReason.WIN:

                print("WIN!")

                # End game
                self._game_state = GameState.WIN
                self.finished.emit()
            
            else:
                self._switch_player()

        return result

    
    def get_piece_at_position(self, position: tuple[int, int, int]) -> Piece:
        return Piece(self._grid[position])
    

    def print_game_board(self):
        """For debugging purposes"""
        for z in range(self._grid_size-1, -1, -1):
            print(self._grid[:,:,z])
            print("")
        
    def _player_id_to_piece(self, player_id: int) -> Piece:
        for piece, stored_id in self._player_ids.items():
            if player_id == stored_id:
                return piece

        raise ValueError("Invalid player id")

    def _set_piece_at_position(self, position: tuple[int, int, int], piece: Piece) -> None:
        """Adds a piece to the position on the board"""
        self._grid[position] = piece.value


    def _get_move_result(self, action: tuple[int, int], piece: Piece) -> MoveResult:
        """Generic move checker. Returns a dict with info of the effects of the move"""
        
        # Is it your turn?
        if not self._is_players_turn(piece):
            return MoveResult(valid=False, reason=MoveReason.NOT_YOUR_TURN)


        # Is it in blounds?
        if not self._is_valid_action(action): 
            return MoveResult(valid=False, reason=MoveReason.OUT_OF_BOUNDS)
        

        position = self.action_to_position(action)

        # Check if it is a winning move
        for direction in self.get_valid_directions(position):
            connected_positions = self.count_pieces_in_open_line(position, direction, piece)
            if connected_positions >= 4:
                return MoveResult(valid=True, reason=MoveReason.WIN)



        opponent_piece = self.get_opponent_piece(piece)
        
        # Check if the move needs to be a blocking move
        if self._rules.must_block:

            # Sjekk alle steder hvor motstander kan legge for å vinne, og sample disse
            opponent_can_win = False
            opponent_win_positions = []

            for a in self.get_possible_actions():
                pos = self.action_to_position(a)
                opponent_wins = self.is_winning_position(pos, opponent_piece)
                if opponent_wins:
                    opponent_can_win = True
                    opponent_win_positions.append(pos)

            # Sjekk om spiller blokkerer en av disse
            if opponent_can_win:
                if position not in opponent_win_positions:
                    return MoveResult(valid=False, reason=MoveReason.MUST_BLOCK)
        


        # Lastly, check if the the move causes the opponent to win if placed on top
        # This is invalid if there are other moves that does not cause the opponent to win
        if self._rules.must_not_give_victory:

            # hvis begge er sanne så er det ugyldig trekk
            move_gives_victory = False
            has_safe_alternative = False


            spot_above = lambda pos: (pos[0], pos[1], pos[2]+1) if pos[2] < self._grid_size-1 else None
            above_position = spot_above(position)
            if above_position is not None:

                # gir plassen over valgt posisjon seier for motstander?
                if self.is_winning_position(above_position, opponent_piece):
                    move_gives_victory = True

                    # vil dette være eneste alternativ?
                
                    for other_action in self.get_possible_actions():
                        # skip denne actionen som vi sjekket allerede
                        if other_action == action: continue

                        pos = self.action_to_position(other_action)
                        spot_above_other_action = spot_above(pos)
                        if spot_above_other_action is None: continue

                        if not self.is_winning_position(spot_above_other_action, opponent_piece):
                            has_safe_alternative = True
                            break

            if move_gives_victory and has_safe_alternative:
                return MoveResult(valid=False, reason=MoveReason.GIVES_OPPONENT_WIN)

        return MoveResult(valid=True, reason=MoveReason.OK)

    
    def is_winning_position(self, position: tuple[int, int, int], piece: Piece) -> bool:
        """Returns True if the position is a winning position for the player id"""
        for direction in self.get_valid_directions(position):
            connected_positions = self.count_pieces_in_open_line(position, direction, piece)
            if connected_positions >= 4:
                return True
        return False
            
    def get_possible_actions(self) -> list[tuple[int, int]]:
        """Returns a list of possible actions"""
        possible_actions = []
        for action in self._actions:
            if self._is_valid_action(action):
                possible_actions.append(action)
        return possible_actions

        
    def count_pieces_in_open_line(
        self,
        position: tuple[int, int, int],
        direction: tuple[int, int, int],
        piece: Piece,
        count_initial_pos: bool = True,
    ) -> int:
        """
        Teller antall brikker med langs retningen.

        Tomme felt ignoreres. Dersom linjen inneholder en brikke
        med en annen ID, returneres -1.
        """
        dx, dy, dz = direction
        count = 1 if count_initial_pos else 0

        # Sjekk begge sider av position
        for sign in (1, -1):
            px, py, pz = position

            for _ in range(self._grid_size):
                px += sign * dx
                py += sign * dy
                pz += sign * dz
                current_pos = (px, py, pz)

                if not self.is_inside_grid(current_pos):
                    break


                current_piece = self.get_piece_at_position(current_pos)

                if current_piece == Piece.EMPTY:
                    continue

                if current_piece != piece:
                    return -1

                count += 1

        return count
        

    def is_valid_direction(self,
        position: tuple[int, int, int],
        direction: tuple[int, int, int],
        length: int = 4,
    ) -> bool:
        """Gir dette en gyldig linje med fire plasser på brettet?"""
        x, y, z = position
        dx, dy, dz = direction

        for start in range(-(length - 1), 1):
            line = [
                (
                    x + (start + i) * dx,
                    y + (start + i) * dy,
                    z + (start + i) * dz,
                )
                for i in range(length)
            ]

            if all(self.is_inside_grid(pos) for pos in line):
                return True

        return False 

    
    def _is_players_turn(self, piece: Piece) -> bool:
        return self._current_piece == piece

    def _is_valid_action(self, action: tuple[int, int]) -> bool:
        x, y = action
        # Inside grid?
        if not action in self._actions: 
            return False

        # Free spot?
        if self._grid[x, y, self._grid_size-1] != 0: 
            return False

        return True
    
    def is_inside_grid(self, position: tuple[int, int, int]) -> bool:
        return 0 <= position[0] < self._grid_size and 0 <= position[1] < self._grid_size and 0 <= position[2] < self._grid_size

    def action_to_position(self, action: tuple[int, int]) -> tuple[int, int, int]:
        """Assumes the action is possible"""
        x, y = action
        z = 0
        col = self._grid[x, y]
        for spot in col:
            if spot == 0:
                break
            z += 1
        return (x, y, z)

    
    def _switch_player(self):
        self._current_piece = self.get_opponent_piece(self._current_piece)

    def get_opponent_piece(self, piece: Piece) -> Piece:
        if piece == Piece.P1:
            return Piece.P2
        if piece == Piece.P2:
            return Piece.P1
        raise ValueError("EMPTY has no opponent")

    def get_piece_from_id(self, player_id: int) -> Piece:
        return self._player_id_to_piece(player_id)

    def get_directions(self):
        return self.DIRECTIONS.copy()
    
    def get_grid_size(self) -> int:
        return self._grid_size

    
    def get_valid_directions(self, position: tuple[int, int, int]):
        return self.pos_to_valid_directions[position]

    def get_position_above(self, position: tuple[int, int, int]) -> tuple[int, int, int] | None:
        """Returns the position above the given position, or None if out of bounds"""
        x, y, z = position
        position_above = (x, y, z + 1)
        if self.is_inside_grid(position_above):
            return position_above
        else:
            return None










    # ==================== FOR BOT ====================



    def get_winning_actions(self, piece: Piece) -> list[tuple[int, int]]:
        return [
            action
            for action in self.get_possible_actions()
            if self.is_winning_position(self.action_to_position(action), piece)
        ]

    def creates_hanging_three(
        self,
        action: tuple[int, int],
        piece: Piece,
    ) -> bool:
        position = self.action_to_position(action)

        # Simuler trekket
        self._set_piece_at_position(position, piece)

        try:
            # Posisjoner motstanderen faktisk kan legge på neste trekk
            playable_positions = {
                self.action_to_position(a)
                for a in self.get_possible_actions()
            }

            x, y, z = position

            for dx, dy, dz in self.get_valid_directions(position):
                # Alle firelinjer som inneholder det nye trekket
                for start in range(-3, 1):
                    line = [
                        (
                            x + (start + i) * dx,
                            y + (start + i) * dy,
                            z + (start + i) * dz,
                        )
                        for i in range(4)
                    ]

                    if not all(self.is_inside_grid(pos) for pos in line):
                        continue

                    values = [
                        self.get_piece_at_position(pos)
                        for pos in line
                    ]

                    # Tre egne brikker og én ledig plass
                    if values.count(piece) == 3 and values.count(Piece.EMPTY) == 1:
                        winning_position = line[values.index(Piece.EMPTY)]

                        # Motstanderen kan ikke blokkere neste trekk
                        if winning_position not in playable_positions:
                            return True

            return False

        finally:
            self._set_piece_at_position(position, Piece.EMPTY)


    def get_winning_actions_after_move(
        self,
        action: tuple[int, int],
        piece: Piece,
    ) -> list[tuple[int, int]]:
        position = self.simulate_move(action, piece)

        try:
            # Trekket er allerede en direkte seier, ikke sjakk matt
            if self.is_winning_position(position, piece):
                return []

            return self.get_winning_actions(piece)

        finally:
            self.undo_move(position)


    def simulate_move(self, action: tuple[int, int], piece: Piece) -> tuple[int, int, int]:
        
        position = self.action_to_position(action)
        self._set_piece_at_position(position, piece)
        return position


    def undo_move(self, position: tuple[int, int, int]) -> None:
        self._set_piece_at_position(position, Piece.EMPTY)