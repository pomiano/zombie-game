import socket
import threading

HOST = "127.0.0.1"
PORT = 2137
clients = set()
running = True

#TODO
#player = [1,0,50,50]
#players = []
#players.append(player)                 - player joined
#players[id] = [id,role,pos_x,pos_y]    - got data from player       

def receive_messages(sock):
    global running
    while running:
        try:
            data, addr = sock.recvfrom(1024)
            clients.add(addr)
            msg = data.decode().strip()
            
            if msg == "/exit":
                print(f"Client {addr} disconnected")
                continue
                
            print(f"Received from {addr}: {msg}")
            #sock.sendto(msg.upper().encode())  # echo
            
        except socket.error:
            if running:
                print("Receive error (socket may be closed)")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
            break

def send_messages(sock):
    global running
    while running:
        try:
            msg = input() # change this to a string with data that server wants to send out
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