@echo off
REM Messaggio di benvenuto
echo Welcome to Hypernode installation process

REM Chiedi all'utente di inserire la porta NON sicura
set /p SERVER_PORT=HTTP server port: 

REM Chiedi all'utente di inserire la porta sicura
set /p SSL_PORT=HTTPS server port: 

REM Attendi un invio
pause

REM Imposta le variabili d'ambiente
set SERVER_PORT=%SERVER_PORT:~-2%
set SSL_PORT=%SSL_PORT:~-3%

REM Esegui docker compose up -d
docker-compose up -d --build