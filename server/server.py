import random
import socket
import threading
import time

HOST = "127.0.0.1"
PORT = 2137
clients = set()
running = True

players = {}
player_id_seq = 0
in_lobby = set()
game_started = False


# TODO
# player = [1,0,50,50]
# players = []
# players.append(player)                 - player joined
# players[id] = [id,role,pos_x,pos_y]    - got data from player

def broadcast(sock, message):
    for addr in in_lobby:
        try:
            sock.sendto(message.encode(), addr)
        except:
            pass


def get_zombie_count(player_count):
    match player_count:
        case p if p <= 2:
            return 1
        case p if p <= 4:
            return 1
        case p if p <= 6:
            return 2
        case p if p <= 8:
            return 3
        case _:
            return max(1, player_count // 4)


def assign_zombies():
    global players
    player_list = list(players.items())
    zombie_count = get_zombie_count(len(player_list))

    chosen_zombies = random.sample(player_list, k=zombie_count)

    for addr, data in player_list:
        pid, role, x, y = data
        if (addr, data) in chosen_zombies:
            role = 1
        else:
            role = 0
        players[addr] = [pid, role, x, y]


def receive_messages(sock):
    global running, player_id_seq, game_started

    while running:
        try:
            data, addr = sock.recvfrom(1024)
            msg = data.decode().strip()

            if msg == '/join' and not game_started:
                if addr not in in_lobby:
                    player_id_seq += 1
                    x = random.randint(30, 189)
                    y = random.randint(30, 149)
                    players[addr] = [player_id_seq, 0, x, y]
                    in_lobby.add(addr)
                    print(f"Player {player_id_seq} joined from {addr}")
                    broadcast(sock, f"J;{player_id_seq};0;{x};{y}")
                    # initialize position for client
                    check_start_conditions(sock)

            elif msg.startswith('P;') and game_started:
                # P;id;role;x;y
                parts = msg.split(";")
                if len(parts) == 5:
                    pid = int(parts[1])
                    _, current_role, _, _ = players.get(addr, [pid, 0, 0, 0])
                    x = max(30, min(189, float(parts[3])))
                    y = max(30, min(149, float(parts[4])))
                    players[addr] = [pid, current_role, x, y]


            elif msg.startswith('C;') and game_started:
                parts = msg.split(";")
                if len(parts) == 3:
                    attacker_id = int(parts[1])
                    victim_id = int(parts[2])

                    attacker = next((p for p in players.values() if p[0] == attacker_id), None)
                    victim = next((p for p in players.values() if p[0] == victim_id), None)

                    if attacker and victim:
                        if attacker[1] == 1:
                            victim = list(victim)
                            victim[1] = 1
                            for addr, data in players.items():
                                if data[0] == victim_id:
                                    players[addr] = victim
                                    print(f"Player {victim_id} got infected by {attacker_id}")
                                    break
        except Exception as e:
            print(f"Error: {e}")


def send_messages(sock):
    global running
    while running:
        try:
            msg = input()  # change this to a string with data that server wants to send out
            if msg == "/exit":
                running = False
                break

            for addr in list(clients):
                try:
                    sock.sendto(msg.encode(), addr)
                except socket.error:
                    clients.remove(addr)

        except (KeyboardInterrupt, EOFError):
            running = False
            break
        except Exception as e:
            print(f"Input error: {e}")
            running = False
            break


def check_start_conditions(sock):
    global game_started

    if len(in_lobby) >= 2 and not game_started:
        game_started = True
        threading.Thread(target=start_game_countdown, args=(sock,)).start()


def start_game_countdown(sock):
    countdown = 5
    while countdown > 0:
        broadcast(sock, f"T;{countdown}")
        time.sleep(1)
        countdown -= 1
    broadcast(sock, "T;0")

    start_game_loop(sock)


def start_game_loop(sock):
    global running, game_started

    assign_zombies()

    while running and game_started:
        for addr, (pid, role, x, y) in players.items():
            msg = f"P;{pid};{role};{x};{y}"
            for client in players:
                try:
                    sock.sendto(msg.encode(), client)
                except:
                    continue
        time.sleep(0.01)  #


def main():
    global running
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((HOST, PORT))
    print(f"Server started on {HOST}:{PORT}.\nType '/exit' to stop the server.\n")

    recv_thread = threading.Thread(target=receive_messages, args=(s,))
    recv_thread.daemon = True
    recv_thread.start()

    send_messages(s)

    running = False
    s.close()
    recv_thread.join()
    print("Server stopped")


main()
