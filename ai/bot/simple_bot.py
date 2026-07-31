from dataclasses import dataclass, field
from environment.game import Game, MoveResult, MoveReason, Piece
import random
from pprint import pprint
import numpy as np




@dataclass
class Weights:
    block_line: float = 1.0
    block_two: float = 1.0
    open_line: float = 1.0      # Enable any line
    open_two: float = 1.0       # Enable two in a row line
    hanging_three: float = 100.0
    block_win: float = 1000.0
    win: float = 1_000_000.0
    can_force_win: float = 100_000.0



class SimpleBot:
    def __init__(self, game: Game, bot_id: int):

        self.bot_id: int = bot_id
        self.bot_piece = game.get_piece_from_id(bot_id)
        self.game = game
        self.last_action_info = {}

        self.last_evaluations = {}

        # weights to evaluate how good an action is
        self.weights = Weights()



    def make_move(self) -> MoveResult:
        opponent_piece = self.game.get_opponent_piece(self.bot_piece)

        # Først, vinn dersom mulig
        best_actions = self.game.get_winning_actions(self.bot_piece)
        selection_reason = "immediate_win"

        # Ellers blokker motstanderens seier
        if not best_actions:
            best_actions = self.game.get_winning_actions(opponent_piece)
            selection_reason = "block_immediate_win"

        # Ellers bruk vanlig evaluering
        if not best_actions:
            evaluations = self.get_all_action_evaluations()

            # TODO For debugging
            self.last_evaluations = evaluations
            ####################

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

        # Legg til info om det beste trekket
        action_info = self.evaluate_action_with_lookahead(best_action)

        result = self.game.request_move(best_action, self.bot_id)

        self.last_action_info = {
            "selection_reason": selection_reason,
            **action_info,
            "move_result": result.reason.name,
        }

        return result
    

    def print_last_action_info(self):
        pprint(self.last_action_info, sort_dicts=False)


    def get_all_action_values(self) -> dict[tuple[int, int], float]:
        """Calculates the value of each bot action in the current game state."""

        action_values: dict[tuple[int, int], float] = {}
        actions: list[tuple[int, int]] = self.game.get_possible_actions()

        for action in actions:
            action_values[action] = self.evaluate_action_with_lookahead(action)

        return action_values
    


    def evaluate_action_with_lookahead(self, action: tuple[int, int]) -> dict:

        own = self.evaluate_action(action, self.bot_piece)

        position = self.game.simulate_move(action, self.bot_piece)

        if self.game.is_winning_position(position, self.bot_piece):
            self.game.undo_move(position)

            return {
                **own,
                "opponent_best_action": None,
                "opponent_best_value": 0.0,
                "opponent_breakdown": {},
                "final_value": self.weights.win,
            }

        opponent_piece = self.game.get_opponent_piece(self.bot_piece)

        opponent_evaluations = [
            self.evaluate_action(opponent_action, opponent_piece)
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
        output = {}
        for action in self.game.get_possible_actions():
            output[action] = self.evaluate_action_with_lookahead(action)
        return output



    def evaluate_action(self, action: tuple[int, int], piece: Piece) -> dict:
        """
        Main function that evaluates the value of a single action.
        """

        opponent_piece = self.game.get_opponent_piece(piece)
        position = self.game.action_to_position(action)

        breakdown = {
            "possible_line": 0.0,
            "block_line": 0.0,
            "block_two": 0.0,
            "block_win": 0.0,
            "enable_two": 0.0,
            "hanging_three": 0.0,
            "win": 0.0,
            "can_force_win": 0.0,
        }

        creates_three = False

        for direction in self.game.get_valid_directions(position):
            n_opponent = self.game.count_pieces_in_open_line(
                position,
                direction,
                opponent_piece,
                count_initial_pos=False,
            )

            n_player = self.game.count_pieces_in_open_line(
                position,
                direction,
                piece,
                count_initial_pos=False,
            )


            # Offensiv evaluering
            if n_player >= 0:
                breakdown["possible_line"] += self.weights.open_line

                if n_player == 1:
                    breakdown["enable_two"] += self.weights.open_two

                elif n_player == 2:
                    creates_three = True

                elif n_player >= 3:
                    breakdown["win"] += self.weights.win

            # Defensiv evaluering
            if n_opponent >= 0:
                if n_opponent == 1:
                    breakdown["block_line"] += self.weights.block_line

                elif n_opponent == 2:
                    breakdown["block_two"] += self.weights.block_two

                elif n_opponent >= 3:
                    breakdown["block_win"] += self.weights.block_win


        if creates_three:
            if self.can_force_win(action, piece):
                breakdown["can_force_win"] += self.weights.can_force_win

            if self.game.creates_hanging_three(action, piece):
                breakdown["hanging_three"] += self.weights.hanging_three



        if self.creates_stacked_winning_positions(action, piece):
            breakdown["can_force_win"] += self.weights.can_force_win

        return {
            "action": action,
            "value": sum(breakdown.values()),
            "breakdown": breakdown,
        }
    


    def can_force_win(self, action: tuple[int, int], piece: Piece, max_depth: int = 8) -> bool:

        opponent_piece = self.game.get_opponent_piece(piece)

        def recursive_search(attack_action: tuple[int, int], depth: int) -> bool:

            attack_position = self.game.simulate_move(attack_action, piece)

            try:
                # Angrepstrekket vant direkte
                if self.game.is_winning_position(attack_position, piece):
                    return True

                # Motstanderen kan vinne i stedet for å blokkere
                if self.game.get_winning_actions(opponent_piece):
                    return False

                forced_blocks = self.game.get_winning_actions(piece)

                # Motstanderen kan bare blokkere 1 posisjon
                if len(forced_blocks) >= 2:
                    return True

                # Trekket skapte ingen tvungen trussel
                if len(forced_blocks) == 0 or depth <= 0:
                    return False

                block_position = self.game.simulate_move(forced_blocks[0], opponent_piece)

                try:
                    next_actions = self.game.get_possible_actions()

                    return any(
                        recursive_search(next_action, depth - 1)
                        for next_action in next_actions
                    )
                finally:
                    self.game.undo_move(block_position)

            finally:
                self.game.undo_move(attack_position)

        return recursive_search(action, max_depth)  


    def creates_stacked_winning_positions(self, action: tuple[int, int], piece: Piece) -> bool:

        placed_position = self.game.simulate_move(action, piece)

        try:
            for next_action in self.game.get_possible_actions():

                lower = self.game.action_to_position(next_action)
                upper = self.game.get_position_above(lower)
                if upper is None:
                    continue

                over_upper = self.game.get_position_above(upper)
                if over_upper is None:
                    continue

                if self.game.is_winning_position(upper, piece):
                    if self.game.is_winning_position(over_upper, piece):
                        return True

            return False

        finally:
            self.game.undo_move(placed_position)