import socket
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse

# Funzione per gestire il traffico tra il client e il server AMQP
def forward_amqp_traffic(source_socket, target_host, target_port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as target_socket:
        target_socket.connect((target_host, target_port))

        def relay(source, target):
            while True:
                data = source.recv(4096)
                if not data:
                    break
                target.sendall(data)

        thread_in = threading.Thread(target=relay, args=(source_socket, target_socket))
        thread_out = threading.Thread(target=relay, args=(target_socket, source_socket))

        thread_in.start()
        thread_out.start()

        thread_in.join()
        thread_out.join()

# Funzione per gestire il traffico HTTP
def handle_http_traffic(client_socket):
    class SocketWrapper(BaseHTTPRequestHandler):
        def __init__(self, request, client_address, server):
            self.raw_requestline = request.recv(4096)
            self.rfile = request.makefile('rb', buffering=0)
            self.wfile = request.makefile('wb', buffering=0)
            self.request = request
            super().__init__(request, client_address, server)

        def do_GET(self):
            parsed_path = urllib.parse.urlparse(self.path)
            if parsed_path.path.startswith("/rabbit"):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"AMQP forwarding not directly handled in HTTP mode.")
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"Not Found")

    SocketWrapper(client_socket, client_socket.getpeername(), None)

# Funzione per distinguere i protocolli e instradare il traffico
def handle_connection(client_socket, target_host, target_port):
    try:
        initial_data = client_socket.recv(4096, socket.MSG_PEEK)
        if initial_data.startswith(b"GET") or initial_data.startswith(b"POST"):
            # Probabile traffico HTTP
            handle_http_traffic(client_socket)
        else:
            # Probabile traffico AMQP
            forward_amqp_traffic(client_socket, target_host, target_port)
    except Exception as e:
        print(f"Errore nella gestione della connessione: {e}")
    finally:
        client_socket.close()

# Funzione principale per avviare il proxy su una singola porta
def start_combined_proxy(listen_host, listen_port, amqp_target_host, amqp_target_port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server_socket:
        server_socket.bind((listen_host, listen_port))
        server_socket.listen(5)
        print(f"Proxy in ascolto su {listen_host}:{listen_port}...")

        while True:
            client_socket, addr = server_socket.accept()
            print(f"Connessione da {addr}")
            threading.Thread(target=handle_connection, args=(client_socket, amqp_target_host, amqp_target_port)).start()

if __name__ == '__main__':
    listen_host = '127.0.0.1'
    listen_port = 90
    amqp_target_host = '127.0.0.1'
    amqp_target_port = 5672

    # Avvia il proxy combinato
    start_combined_proxy(listen_host, listen_port, amqp_target_host, amqp_target_port)
