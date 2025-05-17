from dataclasses import dataclass
from typing import Tuple

ROLE_HUMAN = 0
ROLE_ZOMBIE = 1

MAP_MIN_X, MAP_MAX_X = 30, 189
MAP_MIN_Y, MAP_MAX_Y = 30, 149


@dataclass
class Player:
    id: int
    address: Tuple[str, int]
    role: int = ROLE_HUMAN
    x: float = float(MAP_MIN_X)
    y: float = float(MAP_MIN_Y)

    def format_for_message(self) -> str:
        return f"{self.id};{self.role};{self.x};{self.y}"

    def format_for_state_update(self):
        return f"{self.id},{self.role},{int(self.x)},{int(self.y)}"

