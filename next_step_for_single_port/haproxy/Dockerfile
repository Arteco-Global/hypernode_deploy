# Usa l'immagine base ufficiale di HAProxy
FROM haproxy:latest

# Copia il certificato SSL nella directory di configurazione di HAProxy
COPY my.omniaweb.cloud.pem /usr/local/etc/haproxy/

# Copia il file di configurazione di HAProxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

# Imposta la porta esposta
EXPOSE 90

# Comando di default per avviare HAProxy
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
