@echo off
REM Messaggio di benvenuto
echo Welcome to Hypernode installation process

REM Chiedi all'utente di inserire la porta NON sicura
set /p SERVER_PORT=HTTP server port: 

REM Chiedi all'utente di inserire la porta sicura
set /p SSL_PORT=HTTPS server port: 

REM Chiedi all'utente di inserire la porta sicura
set /p RMQ=Rabbit url: 

REM Chiedi all'utente se è un aggiornamento
set /p IS_UPDATE=Rebuil all the images? [Y/N]: 

REM Attendi un invio
pause

REM Imposta le variabili d'ambiente
set SERVER_PORT=%SERVER_PORT:~-2%
set SSL_PORT=%SSL_PORT:~-3%
set RMQ=%RMQ:amqp://hypernode:hypernode@rabbitmqHypernode:5672%

REM Controlla se è un aggiornamento
if /i "%IS_UPDATE%"=="Y" (
    REM Esegui docker compose up -d --build
    docker-compose up -d --build
) else (
    REM Esegui docker compose up -d senza --build
    docker-compose up -d
)
