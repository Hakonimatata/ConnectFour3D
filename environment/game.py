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
                 GameRules, grid_size=4, print_debug=False):
        
        if p1_id == 0 or p2_id == 0:
            raise ValueError("Player IDs cannot be 0 because 0 represents an empty cell.")
        if p1_id == p2_id:
            raise ValueError("Player IDs must be different.")
        
        
        self._grid_size = grid_size

        # z = 0 is the first plane
        #                         x          y          z
        self._grid = np.zeros((grid_size, grid_size, grid_size), dtype=int)

        self.DIRECTIONS = [ # 13 Unique directions
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
            (1, 1, 0), (1, 0, 1), (0, 1, 1), 
            (1, -1, 0), (1, 0, -1), (0, 1, -1), 
            (1, 1, 1), (1, -1, -1), (-1, 1, -1),
            (-1, -1, 1)
        ]
        self._actions = [(x, y) for x in range(self._grid_size) for y in range(self._grid_size)]

        self._p1_id = p1_id
        self._p2_id = p2_id


        self._current_player_id: int | None = None

        
        self._rules = rules
        self.print_debug = print_debug

        self._game_state = GameState.NOT_STARTED



        # Signal til lyttere utenfra som sier ifra at spillet er ferdig
        self.finished = Signal()


    def start_game(self, starting_player_id: int):

        if starting_player_id != self._p1_id and starting_player_id != self._p2_id:
            raise ValueError("Starting player must be either player 1 or player 2.")
        
        self._current_player_id = starting_player_id
        self._game_state = GameState.PLAYING

    

    def request_move(self, action: tuple[int, int], player_id: int) -> MoveResult:
        """Request move from player, react, and return result of move"""

        if self._game_state == GameState.NOT_STARTED:
            if self.print_debug:
                print("Game is not started")
            return MoveResult(valid=False, reason=MoveReason.INVALID_REQUEST)

        # GET RESULT
        result = self._get_move_result(action, player_id)
        
        

        # REACT TO RESULT Internally brefore returning result

        if result.valid == False:

            if result.reason == MoveReason.NOT_YOUR_TURN:

                if self.print_debug:
                    print("It's not your turn!")

            elif result.reason == MoveReason.OUT_OF_BOUNDS:

                if self.print_debug:
                    print("Action is out of bounds")

            elif result.reason == MoveReason.MUST_BLOCK:

                if self.print_debug:
                    print("Must block")

            elif result.reason == MoveReason.GIVES_OPPONENT_WIN:
                
                if self.print_debug:
                    print("Gives opponent win")

        else: # result.valid == True

            
            # Make move
            pos = self.action_to_position(action)
            self._set_id_at_position(pos, player_id)



            if result.reason == MoveReason.WIN:

                # End game
                self._game_state = GameState.WIN
                self.finished.emit()

                if self.print_debug:
                    print("WIN!")
            
            else:

                self._switch_player()


        return result

    
    def get_id_at_position(self, position: tuple[int, int, int]) -> int:
        return self._grid[position[0], position[1], position[2]]
    

    def print_game_board(self):
        """For debugging purposes"""
        # print(f"Player: {self._current_player_id}'s turn.\n")
        for z in range(self._grid_size-1, -1, -1):
            print(self._grid[:,:,z])
            print("")
        

    def _set_id_at_position(self, position: tuple[int, int, int], id: int) -> None:
        """Adds a piece to the position on the board"""
        self._grid[position[0], position[1], position[2]] = id


    def _get_move_result(self, action: tuple[int, int], player_id: int) -> MoveResult:
        """Generic move checker. Returns a dict with info of the effects of the move"""
        
        # Is it your turn?
        if not self._is_players_turn(player_id):
            return MoveResult(valid=False, reason=MoveReason.NOT_YOUR_TURN)


        # Is it in blounds?
        if not self._is_in_bounds(action): 
            return MoveResult(valid=False, reason=MoveReason.OUT_OF_BOUNDS)
        

        position = self.action_to_position(action)

        # Check if it is a winning move
        for direction in self.DIRECTIONS:
            connected_positions = self.count_pieces_in_open_line(position, direction, player_id)
            if connected_positions >= 4:
                return MoveResult(valid=True, reason=MoveReason.WIN)



        opponent_id = self.get_opponent_id(player_id)
        
        # Check if the move needs to be a blocking move
        if self._rules.must_block:

            # Sjekk alle steder hvor motstander kan legge for å vinne, og sample disse
            opponent_can_win = False
            opponent_win_positions = []

            for a in self.get_possible_actions():
                pos = self.action_to_position(a)
                opponent_wins = self.is_winning_position(pos, opponent_id)
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
                if self.is_winning_position(above_position, opponent_id):
                    move_gives_victory = True

                    # vil dette være eneste alternativ?
                
                    for other_action in self.get_possible_actions():
                        # skip denne actionen som vi sjekket allerede
                        if other_action == action: continue

                        pos = self.action_to_position(other_action)
                        spot_above_other_action = spot_above(pos)
                        if spot_above_other_action is None: continue

                        if not self.is_winning_position(spot_above_other_action, opponent_id):
                            has_safe_alternative = True
                            break

            if move_gives_victory and has_safe_alternative:
                return MoveResult(valid=False, reason=MoveReason.GIVES_OPPONENT_WIN)

        return MoveResult(valid=True, reason=MoveReason.OK)

    
    def is_winning_position(self, position: tuple[int, int, int], player_id: int) -> bool:
        """Returns True if the position is a winning position for the player id"""
        for direction in self.DIRECTIONS:
            connected_positions = self.count_pieces_in_open_line(position, direction, player_id)
            if connected_positions >= 4:
                return True
        return False
            
    def get_possible_actions(self) -> list[tuple[int, int]]:
        """Returns a list of possible actions"""
        possible_actions = []
        for action in self._actions:
            if self._is_in_bounds(action):
                possible_actions.append(action)
        return possible_actions

        
    def count_pieces_in_open_line(
        self,
        position: tuple[int, int, int],
        direction: tuple[int, int, int],
        player_id: int,
        count_initial_pos: bool = True,
    ) -> int:
        """
        Teller antall brikker med player_id langs retningen.

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

                if not self._is_inside_grid(current_pos):
                    break

                current_id = self.get_id_at_position(current_pos)

                if current_id == 0:
                    continue

                if current_id != player_id:
                    return -1

                count += 1

        return count
        

    def is_valid_line(
        self,
        position: tuple[int, int, int],
        direction: tuple[int, int, int],
        length: int = 4,
    ) -> bool:
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

            if all(self._is_inside_grid(pos) for pos in line):
                return True

        return False 


    
    def _is_players_turn(self, player_id: int) -> bool:
        return self._current_player_id == player_id

    def _is_in_bounds(self, action: tuple[int, int]) -> bool:
        x, y = action
        # Inside grid?
        if not action in self._actions: 
            return False

        # Free spot?
        if self._grid[x, y, self._grid_size-1] != 0: 
            return False

        return True
    
    def _is_inside_grid(self, position: tuple[int, int, int]) -> bool:
        return 0 <= position[0] < self._grid_size and 0 <= position[1] < self._grid_size and 0 <= position[2] < self._grid_size

    def action_to_position(self, action: tuple[int, int]) -> tuple[int, int, int]:
        """Assumes the action is possible"""
        x, y = action
        z = self._get_z(action)
        return (x, y, z)

    def _get_z(self, action: tuple[int, int]) -> int:
        """Returns first available free spot in z"""
        x, y = action
        col = self._grid[x, y]
        z = 0
        for spot in col:
            if spot == 0:
                break
            z += 1
        return z
    
    def _switch_player(self):
        if self._current_player_id == self._p1_id: self._current_player_id = self._p2_id
        else: self._current_player_id = self._p1_id

    def get_opponent_id(self, player_id):
        return self._p1_id if player_id != self._p1_id else self._p2_id

    def get_directions(self):
        return self.DIRECTIONS.copy()
    













    # ==================== FOR BOT ====================



    def get_winning_actions(self, player_id: int) -> list[tuple[int, int]]:
        return [
            action
            for action in self.get_possible_actions()
            if self.is_winning_position(
                self.action_to_position(action),
                player_id,
            )
        ]

    def creates_hanging_three(
        self,
        action: tuple[int, int],
        player_id: int,
    ) -> bool:
        position = self.action_to_position(action)

        # Simuler trekket
        self._set_id_at_position(position, player_id)

        try:
            # Posisjoner motstanderen faktisk kan legge på neste trekk
            playable_positions = {
                self.action_to_position(a)
                for a in self.get_possible_actions()
            }

            x, y, z = position

            for dx, dy, dz in self.DIRECTIONS:
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

                    if not all(self._is_inside_grid(pos) for pos in line):
                        continue

                    values = [
                        self.get_id_at_position(pos)
                        for pos in line
                    ]

                    # Tre egne brikker og én ledig plass
                    if values.count(player_id) == 3 and values.count(0) == 1:
                        winning_position = line[values.index(0)]

                        # Motstanderen kan ikke blokkere neste trekk
                        if winning_position not in playable_positions:
                            return True

            return False

        finally:
            self._set_id_at_position(position, 0)

    def get_open_twos_per_plane(
        self,
        position: tuple[int, int, int],
        player_id: int,
        opponent_id: int,
    ) -> dict[str, int]:
        x, y, z = position

        counts = {
            "x": 0,
            "y": 0,
            "z": 0,
            "xy_diag": 0,
            "xy_anti_diag": 0,
        }

        # Hindrer at samme firelinje telles flere ganger i samme plan
        seen_lines = {
            plane: set()
            for plane in counts
        }

        for start_x in range(self._grid_size):
            for start_y in range(self._grid_size):
                for start_z in range(self._grid_size):
                    for dx, dy, dz in self.DIRECTIONS:
                        line = tuple(
                            (
                                start_x + i * dx,
                                start_y + i * dy,
                                start_z + i * dz,
                            )
                            for i in range(4)
                        )

                        if not all(
                            self._is_inside_grid(pos)
                            for pos in line
                        ):
                            continue

                        # Behandle action-posisjonen som tom, også dersom
                        # funksjonen kalles etter at trekket er simulert.
                        values = [
                            0 if pos == position
                            else self.get_id_at_position(pos)
                            for pos in line
                        ]

                        # Nøyaktig to motstanderbrikker og ingen egne
                        if (
                            values.count(opponent_id) != 2
                            or values.count(player_id) != 0
                        ):
                            continue

                        line_key = tuple(sorted(line))

                        planes = []

                        if all(px == x for px, py, pz in line):
                            planes.append("x")

                        if all(py == y for px, py, pz in line):
                            planes.append("y")

                        if all(pz == z for px, py, pz in line):
                            planes.append("z")

                        if all(px - py == x - y for px, py, pz in line):
                            planes.append("xy_diag")

                        if all(px + py == x + y for px, py, pz in line):
                            planes.append("xy_anti_diag")

                        for plane in planes:
                            if line_key not in seen_lines[plane]:
                                seen_lines[plane].add(line_key)
                                counts[plane] += 1

        return counts


    def get_winning_actions_after_move(
        self,
        action: tuple[int, int],
        player_id: int,
    ) -> list[tuple[int, int]]:
        position = self.simulate_move(action, player_id)

        try:
            # Trekket er allerede en direkte seier, ikke sjakk matt
            if self.is_winning_position(position, player_id):
                return []

            return self.get_winning_actions(player_id)

        finally:
            self.undo_move(position)


    def simulate_move(self, action: tuple[int, int], player_id: int) -> tuple[int, int, int]:
        position = self.action_to_position(action)
        self._set_id_at_position(position, player_id)
        return position


    def undo_move(self, position: tuple[int, int, int]) -> None:
        self._set_id_at_position(position, 0)