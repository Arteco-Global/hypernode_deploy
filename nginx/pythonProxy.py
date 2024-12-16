import socket
import threading

# Funzione per gestire il traffico tra il client e il server AMQP
def forward_traffic(source_socket, target_host, target_port):
    # Connessione al broker AMQP di destinazione
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as target_socket:
        target_socket.connect((target_host, target_port))
        
        # Funzione per trasferire i dati dalla sorgente al target
        def relay(source, target):
            while True:
                data = source.recv(4096)
                if not data:
                    break
                target.sendall(data)
        
        # Avvia il thread per inoltrare i dati dal client al server
        thread_in = threading.Thread(target=relay, args=(source_socket, target_socket))
        thread_out = threading.Thread(target=relay, args=(target_socket, source_socket))
        
        thread_in.start()
        thread_out.start()
        
        thread_in.join()
        thread_out.join()

# Funzione per ascoltare il traffico AMQP in ingresso sulla porta 90 e inoltrarlo alla porta 5672
def start_proxy(listen_host, listen_port, target_host, target_port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listen_socket:
        listen_socket.bind((listen_host, listen_port))
        listen_socket.listen(5)
        print(f"Proxy in ascolto su {listen_host}:{listen_port}...")
        
        while True:
            # Accetta la connessione in ingresso
            source_socket, addr = listen_socket.accept()
            print(f"Connessione da {addr}")
            
            # Inizia a inoltrare il traffico verso il target
            threading.Thread(target=forward_traffic, args=(source_socket, target_host, target_port)).start()

if __name__ == '__main__':
    # Definisci gli indirizzi e le porte di ascolto e destinazione
    listen_host = '127.0.0.1'
    listen_port = 90        # Porta da cui ricevi il traffico
    target_host = '127.0.0.1'
    target_port = 5672      # Porta a cui inoltri il traffico
    
start_proxy(listen_host, listen_port, target_host, target_port)