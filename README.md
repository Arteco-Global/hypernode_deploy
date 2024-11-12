# hypernode_deploy

How to deploy and distrubuite hypernode using docker !

Install GIT

    *** debian

    sudo apt update
    sudo apt install git

    *** macOS

    brew install git


Clone the three repos:

- https://github.com/Arteco-Global/hypernode_deploy
- https://github.com/Arteco-Global/hypernode-server
- https://github.com/Arteco-Global/hypernode_server_gui


All the three repos must be cloned in the same folder (e.g "hypernode") (download_repo.sh can be used)

Now using the terminal enter inside the 'hypernode_deploy' folder.
run "sudo sh install_hypernode.sh" on your mac/unix/linux computer.

After the setup:

run "sudo nano /etc/hosts"

Edit the file by adding 

    #hypernode setup

    127.0.0.1 V12230451.lan.omniaweb.cloud
    127.0.0.1 V12230451.my.omniaweb.cloud

    #end hypernode setup

You need to add to your sites, the server 'V12230451' in order to access it.
Default users are located in the "/usr/src/app/users.json" (docker container -> gateway) and are fully editable.
Default user/psw is 'admin'/'admin'.

Cose da fare ---->

Rabbit prima

Aggiungere nome, seriale e timezone da script di installazione

Poter aggiungere camera service su un altra macchina

Demo bac-man

*********** RIAVVIO *************
-> riavvio ffmpeg se va giu telecamera !!!!

