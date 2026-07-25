from dataclasses import dataclass
from environment.game import Game, MoveResult, MoveReason
import random
from pprint import pprint




@dataclass
class Weights:
    # Defense
    block_line: float = 1.0     # Block any opponent line
    block_two: float = 1.0      # Block opponents two in a row line
    block_win: float = 1000.0
    danger_plane: float = 10.0
    
    # Offense
    possible_line: float = 1.0  # Enable any line
    enable_two: float = 1.0     # Enable two in a row line
    enable_three: float = 0.0   # Enable three in a row line
    three_and_opponent_cannot_block: float = 90.0
    checkmate: float = 100_000.0
    win: float = 1_000_000.0



class SimpleBot:
    def __init__(self, game: Game, bot_id: int):

        self.bot_id: int = bot_id
        self.game = game
        self.last_action_info = {}
        self.weights = Weights() # default weights



    def make_move(self) -> MoveResult:
        opponent_id = self.game.get_opponent_id(self.bot_id)

        # 1. Vinn dersom mulig
        best_actions = self.game.get_winning_actions(self.bot_id)
        selection_reason = "immediate_win"

        # 2. Ellers blokker motstanderens seier
        if not best_actions:
            best_actions = self.game.get_winning_actions(opponent_id)
            selection_reason = "block_immediate_win"

        # 3. Ellers bruk vanlig evaluering
        if not best_actions:
            evaluations = self.get_all_action_evaluations()


            # TODO testing
            self.last_evaluations = evaluations

            if not evaluations:
                self.last_action_info = {
                    "selection_reason": "no_possible_actions"
                }

                return MoveResult(
                    valid=False,
                    reason=MoveReason.INVALID_REQUEST,
                )

            highest_value = max(
                info["final_value"]
                for info in evaluations.values()
            )

            best_actions = [
                action
                for action, info in evaluations.items()
                if info["final_value"] == highest_value
            ]

            selection_reason = "highest_evaluation"

        best_action = random.choice(best_actions)

        # Må gjøres før det ekte trekket endrer brettet
        action_info = self.evaluate_action_with_lookahead(best_action)

        result = self.game.request_move(best_action, self.bot_id)

        self.last_action_info = {
            "selection_reason": selection_reason,
            **action_info,
            "move_result": result.reason.name,
        }

        return result
    

    def print_last_action(self):
        pprint(self.last_action_info, sort_dicts=False)


    def get_all_action_values(self) -> dict[tuple[int, int], float]:
        """Calculates the value of each bot action in the current game state."""

        action_values: dict[tuple[int, int], float] = {}
        actions: list[tuple[int, int]] = self.game.get_possible_actions()

        for action in actions:
            action_values[action] = self.calculate_action_value_with_lookahead(action)

        return action_values
    


    def evaluate_action_with_lookahead(
        self,
        action: tuple[int, int],
    ) -> dict:

        own = self.evaluate_action(action, self.bot_id)

        position = self.game.simulate_move(action, self.bot_id)

        if self.game.is_winning_position(position, self.bot_id):
            self.game.undo_move(position)

            return {
                **own,
                "opponent_best_action": None,
                "opponent_best_value": 0.0,
                "opponent_breakdown": {},
                "final_value": self.weights.win,
            }

        opponent_id = self.game.get_opponent_id(self.bot_id)

        opponent_evaluations = [
            self.evaluate_action(opponent_action, opponent_id)
            for opponent_action in self.game.get_possible_actions()
        ]

        best_opponent = max(
            opponent_evaluations,
            key=lambda info: info["value"],
            default=None,
        )

        self.game.undo_move(position)

        opponent_value = (
            best_opponent["value"]
            if best_opponent is not None
            else 0.0
        )

        return {
            **own,
            "opponent_best_action": (
                best_opponent["action"]
                if best_opponent is not None
                else None
            ),
            "opponent_best_value": opponent_value,
            "opponent_breakdown": (
                best_opponent["breakdown"]
                if best_opponent is not None
                else {}
            ),
            "final_value": own["value"] - opponent_value,
        }
    

    def get_all_action_evaluations(self) -> dict[tuple[int, int], dict]:
        return {
            action: self.evaluate_action_with_lookahead(action)
            for action in self.game.get_possible_actions()
        }


    def evaluate_action(
        self,
        action: tuple[int, int],
        player_id: int | None = None,
    ) -> dict:


        opponent_id = self.game.get_opponent_id(player_id)
        position = self.game.action_to_position(action)

        breakdown = {
            "possible_line": 0.0,
            "block_line": 0.0,
            "block_two": 0.0,
            "block_win": 0.0,
            "enable_two": 0.0,
            "enable_three": 0.0,
            "hanging_three": 0.0,
            "danger_plane": 0.0,
            "win": 0.0,
            "checkmate": 0.0,
        }

        # Plan der dette trekket blokkerer en motstander-toer
        blocked_two_planes: set[str] = set()

        for direction in self.game.DIRECTIONS:
            n_opponent = self.game.count_pieces_in_open_line(
                position,
                direction,
                opponent_id,
                count_initial_pos=False,
            )

            n_player = self.game.count_pieces_in_open_line(
                position,
                direction,
                player_id,
                count_initial_pos=False,
            )

            is_valid_line = self.game.is_valid_line(
                position,
                direction,
            )

            # Offensiv evaluering
            if is_valid_line and n_player >= 0:
                breakdown["possible_line"] += (
                    self.weights.possible_line
                )

                if n_player == 1:
                    breakdown["enable_two"] += self.weights.enable_two

                elif n_player == 2:
                    breakdown["enable_three"] += (
                        self.weights.enable_three
                    )

                elif n_player >= 3:
                    breakdown["win"] = self.weights.win

            # Defensiv evaluering
            if is_valid_line and n_opponent >= 0:
                if n_opponent == 1:
                    breakdown["block_line"] += self.weights.block_line

                elif n_opponent == 2:
                    breakdown["block_two"] += self.weights.block_two

                    dx, dy, dz = direction

                    if dx == 0:
                        blocked_two_planes.add("x")
                    if dy == 0:
                        blocked_two_planes.add("y")
                    if dz == 0:
                        blocked_two_planes.add("z")
                    if dx == dy:
                        blocked_two_planes.add("xy_diag")
                    if dx == -dy:
                        blocked_two_planes.add("xy_anti_diag")

                elif n_opponent >= 3:
                    breakdown["block_win"] += self.weights.block_win

        # Tell motstanderens åpne toere i planene som trekket blokkerer
        twos_per_plane = self.game.get_open_twos_per_plane(
            position,
            player_id,
            opponent_id,
        )

        max_twos_in_blocked_plane = max(
            (
                twos_per_plane[plane]
                for plane in blocked_two_planes
            ),
            default=0,
        )

        # block_two gir allerede grunnverdien for én toer.
        # danger_plane gir ekstra verdi for flere toere i samme plan.
        if max_twos_in_blocked_plane >= 2:
            breakdown["danger_plane"] += (
                (max_twos_in_blocked_plane - 1)
                * self.weights.danger_plane
            )

        winning_actions_next_turn = (
            self.game.get_winning_actions_after_move(
                action,
                player_id,
            )
        )

        if len(winning_actions_next_turn) >= 2:
            breakdown["checkmate"] = self.weights.checkmate

        if self.game.creates_hanging_three(action, player_id):
            breakdown["hanging_three"] += (
                self.weights.three_and_opponent_cannot_block
            )

        return {
            "action": action,
            "value": sum(breakdown.values()),
            "breakdown": breakdown,
        }
    

    def calculate_action_value(
        self,
        action: tuple[int, int],
        player_id: int | None = None,
    ) -> float:
        return self.evaluate_action(action, player_id)["value"]