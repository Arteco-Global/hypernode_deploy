#!/bin/bash

# Funzione per fermare tutti i container Docker
stop_containers() {
    echo "🚦 Fermando tutti i container Docker..."
    docker stop $(docker ps -q) >/dev/null 2>&1 && echo "✅ Tutti i container sono stati fermati." || echo "❌ Errore durante l'arresto dei container."
}

# Funzione per avviare tutti i container Docker
start_containers() {
    echo "🚀 Avviando tutti i container Docker..."
    docker start $(docker ps -aq) >/dev/null 2>&1 && echo "✅ Tutti i container sono stati avviati." || echo "❌ Errore durante l'avvio dei container."
}

# Funzione per riavviare tutti i container Docker
restart_containers() {
    echo "🔄 Riavviando tutti i container Docker..."
    docker restart $(docker ps -aq) >/dev/null 2>&1 && echo "✅ Tutti i container sono stati riavviati." || echo "❌ Errore durante il riavvio dei container."
}

# Verifica del comando passato
if [ "$#" -eq 0 ]; then
    echo "❌ Nessun comando specificato. Usa: stop | start | restart"
    exit 1
fi

# Esegui il comando appropriato
case "$1" in
    stop)
        stop_containers
        ;;
    start)
        start_containers
        ;;
    restart)
        restart_containers
        ;;
    *)
        echo "❌ Comando non riconosciuto. Usa: stop | start | restart"
        exit 1
        ;;
esac
