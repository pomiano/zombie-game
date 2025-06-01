import logging
import random
import socket
import threading
import time
from typing import Optional, Tuple, Dict, Set, Iterable, List

import config
from player import Player

logger = logging.getLogger(__name__)


class GameServer:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.sock: Optional[socket.socket] = None
        self.running = True

        self.players_by_addr: Dict[Tuple[str, int], Player] = {}
        self.players_by_id: Dict[int, Player] = {}
        self.players_nicknames_by_id: Dict[int, Tuple[str, bool]] = {}

        self._player_id_seq = 0

        self._lobby_addrs: Set[Tuple[str, int]] = set()
        self._game_started = False
        self._game_loop_active = False

        self._receive_thread: Optional[threading.Thread] = None
        self._game_loop_thread: Optional[threading.Thread] = None

        self._server_lock = threading.Lock()

    def _get_next_player_id(self) -> int:
        self._player_id_seq += 1
        return self._player_id_seq

    def _broadcast_message(self, message: str, target_addrs: Optional[Iterable[Tuple[str, int]]] = None):
        if not self.sock:
            return

        if target_addrs is None:
            target_addrs = list(self.players_by_addr.keys())

        encoded_message = message.encode()

        for addr in list(target_addrs):
            try:
                self.sock.sendto(encoded_message, addr)
            except socket.error as e:
                logger.warning(f"Błąd gniazda podczas wysyłania do {addr}: {e}.")
            except Exception as e:
                logger.error(f"Nieoczekiwany błąd podczas wysyłania do {addr}: {e}")

    def _get_zombie_count(self) -> int:
        player_count = len(self.players_by_addr)
        if player_count == 0: return 0
        if player_count <= 2: return 1
        if player_count <= 4: return 1
        if player_count <= 6: return 2
        if player_count <= 8: return 3
        return max(1, player_count // 4)

    def _assign_zombies(self):
        with self._server_lock:
            if not self.players_by_addr:
                return

            all_players_list = list(self.players_by_addr.values())
            zombie_count = self._get_zombie_count()

            chosen_zombies = random.sample(all_players_list, k=zombie_count)

            for p_obj in all_players_list:
                if p_obj in chosen_zombies:
                    p_obj.role = config.ROLE_ZOMBIE
                else:
                    p_obj.role = config.ROLE_HUMAN

            logger.info(
                f"Przydzielono role: {len(chosen_zombies)} zombie, {len(all_players_list) - len(chosen_zombies)} ludzi.")

    def _handle_join_request(self, addr: Tuple[str, int], nickname: str):
        if self._game_started:
            logger.info(f"Gra już się rozpoczęła. Ignorowanie prośby o dołączenie od {addr}.")
            return

        if addr in self.players_by_addr:
            logger.warning(f"Gracz z {addr} próbował dołączyć ponownie, będąc już na liście.")
            return

        player_id = self._get_next_player_id()
        pos_x = float(random.randint(config.MAP_MIN_X, config.MAP_MAX_X))
        pos_y = float(random.randint(config.MAP_MIN_Y, config.MAP_MAX_Y))

        new_player = Player(id=player_id, address=addr, x=pos_x, y=pos_y, role=config.ROLE_HUMAN)

        self.players_by_addr[addr] = new_player
        self.players_by_id[player_id] = new_player
        self._lobby_addrs.add(addr)


        self.players_nicknames_by_id[player_id] = {
            "nickname": nickname,
            "ready": False
        }

        logger.info(f"Gracz {player_id} ({addr}, nick: {nickname}) dołączył do lobby.")

        all_players_info = []
        for pid, pdata in self.players_nicknames_by_id.items():
            nick = pdata["nickname"]
            ready = pdata["ready"]
            all_players_info.append(str(pid))
            all_players_info.append(nick)
            all_players_info.append("1" if ready else "0")

        join_confirm_msg_self = config.MSG_PREFIX_JOIN_CONFIRMATION +";" + str(player_id) +";"+ str(pos_x)+";" + str(pos_y)+ ";" + ";".join(all_players_info)
        logger.info(f"Wysyłanie potwierdzenia do nowego gracza ({addr}): {join_confirm_msg_self}")

        if self.sock:
            self.sock.sendto(join_confirm_msg_self.encode(), addr)
            broadcast_msg = config.MSG_PREFIX_LOBBY + ";" + ";".join(all_players_info)
            #logger.info(f"Wysyłanie broadcastu do innych graczy: {broadcast_msg}")
            for other_addr in self.players_by_addr:
                if other_addr != addr:
                    self.sock.sendto(broadcast_msg.encode(), other_addr)



    def _handle_position_update(self, addr: Tuple[str, int], parts: List[str]):
        player = self.players_by_addr.get(addr)
        if not player or not self._game_started:
            return

        try:
            sent_pid = int(parts[1])
            new_x = float(parts[3])
            new_y = float(parts[4])

            if sent_pid != player.id:
                logger.warning(
                    f"Niezgodność ID dla {addr}. Oczekiwano {player.id}, otrzymano {sent_pid}. Ignorowanie aktualizacji.")
                return

            player.x = max(config.MAP_MIN_X, min(config.MAP_MAX_X, new_x))
            player.y = max(config.MAP_MIN_Y, min(config.MAP_MAX_Y, new_y))
            # Rola gracza (player.role) jest autorytatywna po stronie serwera i nie jest aktualizowana z wiadomości P od klienta.
        except (IndexError, ValueError) as e:
            logger.warning(f"Nieprawidłowa aktualizacja pozycji od {addr}: {parts}. Błąd: {e}")

    def _handle_attack(self, sender_addr: Tuple[str, int], parts: List[str]):
        # Format: C;id_atakujacego;id_ofiary
        attacker_player = self.players_by_addr.get(sender_addr)
        if not attacker_player or not self._game_started:
            return

        try:
            reported_attacker_id = int(parts[1])
            victim_id = int(parts[2])

            if reported_attacker_id != attacker_player.id:
                logger.warning(f"Wiadomość o ataku od {sender_addr} z niezgodnym ID atakującego ({reported_attacker_id} vs {attacker_player.id})")
                return

            victim_player = self.players_by_id.get(victim_id)

            if not victim_player:
                logger.debug(f"Atakujący {attacker_player.id} próbował zaatakować nieistniejącą ofiarę {victim_id}")
                return

            if attacker_player.role != victim_player.role:
                victim_player.role = config.ROLE_ZOMBIE
                attacker_player.role = config.ROLE_ZOMBIE
                
                logger.info(f"Gracz {victim_player.id} zainfekowany przez Gracza {attacker_player.id}.")
                self._broadcast_message(
                    f"{config.MSG_CLIENT_COLLISION};{victim_player.id};{config.ROLE_ZOMBIE}")
                self._check_game_over_conditions()
        except (IndexError, ValueError) as e:
            logger.warning(f"Nieprawidłowa wiadomość o ataku od {sender_addr}: {parts}. Błąd: {e}")

    def handle_client_ready(self, player_id: int):
        if player_id in self.players_nicknames_by_id:
            self.players_nicknames_by_id[player_id]["ready"] = True
            logger.info(f"Gracz {player_id} oznaczył się jako gotowy.")
            self.send_lobby_update()
            self._check_start_conditions()
        else:
            logger.warning(f"Otrzymano MSG_CLIENT_READY z nieznanym player_id: {player_id}")

    def handle_player_left(self, player_id: int):
        if player_id in self.players_nicknames_by_id:
            nickname = self.players_nicknames_by_id[player_id]["nickname"]
            del self.players_nicknames_by_id[player_id]
            logger.info(f"Gracz {player_id} ({nickname}) opuścił lobby.")

            addr_to_remove = next((addr for addr, player in self.players_by_addr.items() if player.id == player_id),
                                  None)

            if addr_to_remove is not None:
                del self.players_by_addr[addr_to_remove]
                logger.info(f"Usunięto adres {addr_to_remove} z players_by_addr")
            else:
                logger.warning(f"Nie znaleziono adresu dla player_id {player_id} w players_by_addr")

            self.send_lobby_update()
        else:
            logger.warning(f"Próba usunięcia gracza {player_id}, który nie istnieje.")

    def reset_players_ready(self):
        for pid in self.players_nicknames_by_id:
            self.players_nicknames_by_id[pid]["ready"] = False

    def send_lobby_update(self):
        all_players_info = []
        for pid, pdata in self.players_nicknames_by_id.items():
            nick = pdata["nickname"]
            ready = pdata["ready"]
            all_players_info.append(str(pid))
            all_players_info.append(nick)
            all_players_info.append("1" if ready else "0")

        broadcast_msg = config.MSG_PREFIX_LOBBY + ";" + ";".join(all_players_info)
        logger.info(f"Wysyłanie zaktualizowanej listy graczy: {broadcast_msg}")
        for addr in self.players_by_addr:
            self.sock.sendto(broadcast_msg.encode(), addr)

    def _receive_messages_loop(self):
        if not self.sock: return
        logger.info("Receiving messages...")
        while self.running:
            try:
                data, addr = self.sock.recvfrom(1024)
                msg = data.decode().strip()

                if not msg: continue

                parts = msg.split(";")
                command = parts[0]

                if command == config.MSG_CLIENT_JOIN_REQUEST:
                    parts = msg.split(";", 1)
                    if len(parts) == 2:
                        nickname = parts[1].strip()
                        self._handle_join_request(addr, nickname)
                    else:
                        logger.warning(f"Brak nicku w wiadomości dołączenia od {addr}")

                elif command == config.MSG_CLIENT_POSITION_UPDATE and len(parts) == 5:
                    if self._game_started:
                        self._handle_position_update(addr, parts)

                elif command == config.MSG_CLIENT_COLLISION and len(parts) == 3:
                    if self._game_started:
                        self._handle_attack(addr, parts)

                elif command == config.MSG_CLIENT_READY:
                    if len(parts) >= 2:
                        try:
                            player_id = int(parts[1])
                            self.handle_client_ready(player_id)
                        except ValueError:
                            logger.error("Nieprawidłowe ID gracza w MSG_CLIENT_READY")

                elif command == config.MSG_CLIENT_LEFT:
                    if len(parts) >= 2:
                        try:
                            player_id = int(parts[1])
                            self.handle_player_left(player_id)
                        except ValueError:
                            logger.error("Nieprawidłowe ID gracza w MSG_CLIENT_LEFT")


            except socket.timeout:
                continue  # Normalne, jeśli gniazdo ma timeout
            except OSError as e:
                if self.running:
                    logger.error(f"Błąd gniazda w pętli odbierania: {e}")
                if not self.running:
                    break
            except Exception as e:
                logger.error(f"Błąd w pętli odbierania wiadomości: {e}", exc_info=True)

    def _check_start_conditions(self):
        with self._server_lock:
            if len(self._lobby_addrs) >= config.MIN_PLAYERS_TO_START \
                    and self.are_all_players_ready() and not self._game_started:
                self._game_started = True
                self._game_loop_active = False
                logger.info(
                    f"Osiągnięto minimalną liczbę graczy ({config.MIN_PLAYERS_TO_START}). Rozpoczynanie odliczania.")

                threading.Thread(target=self._start_game_countdown_sequence, daemon=True,
                                 name="CountdownThread").start()

    def are_all_players_ready(self) -> bool:
        return all(player["ready"] for player in self.players_nicknames_by_id.values())

    def _start_game_countdown_sequence(self):
        for i in range(config.GAME_COUNTDOWN_SECONDS, -1, -1):
            self._broadcast_message(
                f"{config.MSG_PREFIX_GAME_TIMER};{i}",
                list(self._lobby_addrs)
            )
            time.sleep(1)
        if not self.running: return

        if len(self.players_by_addr) < config.MIN_PLAYERS_TO_START:
            logger.info("Niewystarczająca liczba graczy na koniec odliczania. Przerywanie startu gry.")
            self._broadcast_message(f"{config.MSG_PREFIX_GAME_TIMER};ABORT", list(self._lobby_addrs))
            self._reset_to_lobby_state(inform_clients=False)
            return

        self._lobby_addrs.clear()
        self._assign_zombies()

        logger.info("Game starts now !")
        self._game_loop_active = True

        threading.Thread(target=self._game_timer, daemon=True, name="GameTimerThread").start()

        if self._game_loop_thread is None or not self._game_loop_thread.is_alive():
            self._game_loop_thread = threading.Thread(target=self._game_update_loop, name="GameLoopThread",
                                                      daemon=True)
            self._game_loop_thread.start()

    def _game_timer(self):
        time.sleep(config.GAME_DURATION_SECONDS)
        if self._game_started and self.running:
            logger.info("Czas gry upłynął. Kończenie gry.")
            self._broadcast_message(f"{config.MSG_PREFIX_GAME_OVER}")
            self._reset_to_lobby_state(inform_clients=False)

    def _game_update_loop(self):
        logger.info("Pętla aktualizacji gry uruchomiona.")
        while self.running and self._game_started and self._game_loop_active:
            loop_start_time = time.monotonic()

            player_state_parts = [p.format_for_state_update() for p in self.players_by_addr.values()]

            if player_state_parts:
                game_state_message = f"{config.MSG_PREFIX_PLAYER_STATE_UPDATE};" + "|".join(player_state_parts)
                self._broadcast_message(game_state_message)

            elapsed_time = time.monotonic() - loop_start_time
            sleep_duration = config.SERVER_TICK_RATE - elapsed_time
            if sleep_duration > 0:
                time.sleep(sleep_duration)

        logger.info("Pętla aktualizacji gry zatrzymana.")
        self._game_loop_active = False

    def _check_game_over_conditions(self) -> bool:
        if not self._game_started:
            return False

        if not self.players_by_addr and self._game_started:
            logger.info("Wszyscy gracze opuścili grę. Koniec gry.")
            self._reset_game("Wszyscy gracze się rozłączyli.")
            return True

        if not self.players_by_addr:
            return False

        humans_remaining = 0
        zombies_remaining = 0
        for player in self.players_by_addr.values():
            if player.role == config.ROLE_HUMAN:
                humans_remaining += 1
            else:
                zombies_remaining += 1

        game_over_msg_payload = ""
        if humans_remaining == 0 and zombies_remaining > 0:  # Wszyscy ludzie zainfekowani
            game_over_msg_payload = "Zombie wygrały! Wszyscy ludzie zostali zainfekowani."
        elif zombies_remaining == 0 and humans_remaining > 0:  # Wszyscy zombie pokonani/rozłączeni
            game_over_msg_payload = "Ludzie wygrali! Wszystkie zombie zostały wyeliminowane lub opuściły grę."

        if game_over_msg_payload:
            logger.info(f"Koniec Gry: {game_over_msg_payload}")
            self._broadcast_message(f"{config.MSG_PREFIX_GAME_OVER};{game_over_msg_payload}")
            #self._reset_game(game_over_msg_payload)
            self._reset_to_lobby_state(inform_clients=False)
            return True
        return False

    def _reset_to_lobby_state(self, inform_clients=True):
        self._game_started = False
        self._game_loop_active = False

        self.reset_players_ready()

        self._lobby_addrs.clear()
        for addr, player_obj in self.players_by_addr.items():
            self._lobby_addrs.add(addr)
            player_obj.role = config.ROLE_HUMAN

        logger.info("Serwer zresetowany do stanu lobby. Gotowy na nową grę.")
        if inform_clients:
            self._broadcast_message(f"{config.MSG_PREFIX_SERVER_MESSAGE};Gra została zresetowana. Powrót do lobby.")

    def _reset_game(self, reason: str):
        logger.info(f"Resetowanie gry. Powód: {reason}")
        self._reset_to_lobby_state(
            inform_clients=False)
        self._check_start_conditions()

    def _admin_command_loop(self):
        logger.info("Konsola admina uruchomiona. Wpisz '/exit' aby zatrzymać, '/status' po informacje.")
        while self.running:
            try:
                cmd_input = input().strip()
                if not cmd_input: continue

                parts = cmd_input.split(" ", 1)
                command = parts[0].lower()

                if command == "/exit":
                    logger.info("Admin: komenda /exit. Zamykanie serwera...")
                    self.running = False
                    break
                elif command == "/status":
                    logger.info("--- Status Serwera ---")
                    logger.info(
                        f"  Działa: {self.running}, Gra Rozpoczęta: {self._game_started}, Pętla Aktywna: {self._game_loop_active}")
                    logger.info(f"  Gracze Online ({len(self.players_by_addr)}):")
                    for p_obj in self.players_by_addr.values():
                        role_str = "Zombie" if p_obj.role == config.ROLE_ZOMBIE else "Człowiek"
                        logger.info(
                            f"    ID: {p_obj.id}, Adres: {p_obj.address}, Rola: {role_str}, Poz: ({p_obj.x:.1f},{p_obj.y:.1f})")
                    logger.info(f"  Gracze w Lobby ({len(self._lobby_addrs)}): {list(self._lobby_addrs)}")
                else:
                    logger.info(f"Admin: Nieznana komenda '{command}'")

            except EOFError:
                logger.info("Konsola admina: EOF (np. koniec danych wejściowych). Zatrzymywanie pętli admina.")
                break
            except KeyboardInterrupt:
                logger.info("Konsola admina: Ctrl+C. Zamykanie serwera...")
                self.running = False
                break
            except Exception as e:
                logger.error(f"Błąd w pętli komend admina: {e}")

        if self.running:
            self.running = False
        logger.info("Pętla komend admina zatrzymana.")

    def start(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.host, self.port))
            self.sock.settimeout(1.0)
            logger.info(f"Serwer uruchomiony na {self.host}:{self.port}.")

            self._receive_thread = threading.Thread(target=self._receive_messages_loop, name="ReceiveThread",
                                                    daemon=True)
            self._receive_thread.start()

            self._admin_command_loop()

        except OSError as e:
            logger.error(f"Nie udało się uruchomić serwera: {e}")
            self.running = False
        except Exception as e:
            logger.error(f"Nieoczekiwany błąd podczas uruchamiania serwera: {e}", exc_info=True)
            self.running = False
        finally:
            self.shutdown()

    def shutdown(self):
        logger.info("Serwer jest zamykany...")
        self.running = False
        self._game_loop_active = False

        if self._game_loop_thread and self._game_loop_thread.is_alive():
            logger.info("Oczekiwanie na zakończenie wątku pętli gry...")
            self._game_loop_thread.join(timeout=2)
            if self._game_loop_thread.is_alive():
                logger.warning("Wątek pętli gry nie zakończył się w wyznaczonym czasie.")

        if self.sock:
            logger.info("Zamykanie gniazda serwera.")
            self.sock.close()
            self.sock = None

        if self._receive_thread and self._receive_thread.is_alive():
            logger.info("Oczekiwanie na zakończenie wątku odbierającego...")
            self._receive_thread.join(timeout=2)
            if self._receive_thread.is_alive():
                logger.warning("Wątek odbierający nie zakończył się w wyznaczonym czasie.")

        logger.info("Serwer zatrzymany.")