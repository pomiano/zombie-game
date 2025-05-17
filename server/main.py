import logging
import config
from game_server import GameServer


def setup_logging():
    log_level_name = getattr(config, 'LOG_LEVEL', 'INFO').upper()
    log_level = getattr(logging, log_level_name, logging.INFO)

    logging.basicConfig(
        level=log_level,
        format=getattr(config, 'LOG_FORMAT', '%(asctime)s - %(levelname)s - %(message)s')
    )


if __name__ == "__main__":
    setup_logging()

    server_host = config.HOST
    server_port = config.PORT

    game_server = GameServer(host=server_host, port=server_port)
    game_server.start()  # Uruchom serwer
