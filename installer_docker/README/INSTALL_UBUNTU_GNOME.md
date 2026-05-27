# Installazione grafica su Ubuntu – How To

Guida **schematica e copiabile** per installare e usare **uSee Service Suite Launcher** con privilegi amministrativi.

---

## 1️⃣ Installazione applicazione (.deb)

1. Copiare il file `.deb` sulla macchina Ubuntu
2. **Doppio click** sul file `.deb`
3. Si apre *App Center*
4. Cliccare **Installa**
5. Inserire la password quando richiesta

➡️ A fine installazione comparirà nel menu:
- **uSee Service Suite Launcher**

---

## 2️⃣ Creazione avvio “Amministratore” (una sola volta)

### 2.1 Creare lo script di avvio

Aprire un terminale e copiare **tutto**:

```bash
mkdir -p ~/.local/bin

cat > ~/.local/bin/ussinstaller-admin-launch <<'EOF'
#!/bin/sh

# Permette a root di usare il display grafico corrente
xhost +SI:localuser:root >/dev/null

# Avvia l'app come amministratore
exec pkexec env DISPLAY="$DISPLAY" \
  /opt/uSee-Service-Suite-Launcher/ussinstaller --no-sandbox
EOF

chmod +x ~/.local/bin/ussinstaller-admin-launch
```

---

### 2.2 Creare il launcher grafico

```bash
nano ~/.local/share/applications/ussinstaller-admin.desktop
```

Incollare:

```ini
[Desktop Entry]
Name=uSee Service Suite Launcher (Amministratore)
Comment=Avvio amministrativo uSee Service Suite
Exec=/home/arteco/.local/bin/ussinstaller-admin-launch
Terminal=false
Type=Application
Icon=ussinstaller
Categories=Utility;
```

Salvare e chiudere.

---

### 2.3 Aggiornare il menu

```bash
update-desktop-database ~/.local/share/applications
```

➡️ **Logout / Login**

---

## 3️⃣ Utilizzo

Dal menu Applicazioni:

- **uSee Service Suite Launcher** → avvio normale
- **uSee Service Suite Launcher (Amministratore)** → avvio con privilegi

All’avvio amministratore:
1. Comparirà la richiesta password
2. L’app partirà con privilegi root

---

## 4️⃣ Test finale

1. Riavviare la macchina
2. Fare login grafico
3. Avviare **uSee Service Suite Launcher (Amministratore)**
4. Verificare install / update / uninstall

Se funziona → setup completato ✅

---

## Note
- Procedura valida per **Ubuntu GNOME (X11)**
- Pensata per **server / appliance dedicate**
- Nessun uso di SSH o terminale richiesto per il supporto (dopo setup iniziale)

---

# ENG — Graphical installation on Ubuntu – How To

A **concise, copy-ready** guide to install and use **uSee Service Suite Launcher** with administrative privileges.

---

## 1️⃣ Application installation (.deb)

1. Copy the `.deb` file to the Ubuntu machine
2. **Double-click** the `.deb` file
3. *App Center* opens
4. Click **Install**
5. Enter the password when prompted

➡️ After installation you will find in the menu:
- **uSee Service Suite Launcher**

---

## 2️⃣ Create “Administrator” launcher (one-time setup)

### 2.1 Create the launch script

Open a terminal and copy **everything**:

```bash
mkdir -p ~/.local/bin

cat > ~/.local/bin/ussinstaller-admin-launch <<'EOF'
#!/bin/sh

# Allow root to use the current graphical display
xhost +SI:localuser:root >/dev/null

# Start the app as administrator
exec pkexec env DISPLAY="$DISPLAY" \
  /opt/uSee-Service-Suite-Launcher/ussinstaller --no-sandbox
EOF

chmod +x ~/.local/bin/ussinstaller-admin-launch
```

---

### 2.2 Create the graphical launcher

```bash
nano ~/.local/share/applications/ussinstaller-admin.desktop
```

Paste:

```ini
[Desktop Entry]
Name=uSee Service Suite Launcher (Administrator)
Comment=Administrative launch of uSee Service Suite
Exec=/home/arteco/.local/bin/ussinstaller-admin-launch
Terminal=false
Type=Application
Icon=ussinstaller
Categories=Utility;
```

Save and close.

---

### 2.3 Update the menu

```bash
update-desktop-database ~/.local/share/applications
```

➡️ **Logout / Login**

---

## 3️⃣ Usage

From the Applications menu:

- **uSee Service Suite Launcher** → normal launch
- **uSee Service Suite Launcher (Administrator)** → launch with privileges

When starting as administrator:
1. A password prompt will appear
2. The app will start with root privileges

---

## 4️⃣ Final test

1. Reboot the machine
2. Log in graphically
3. Start **uSee Service Suite Launcher (Administrator)**
4. Verify install / update / uninstall

If it works → setup complete ✅

---

## Notes
- Procedure valid for **Ubuntu GNOME (X11)**
- Intended for **dedicated server / appliance**
- No SSH or terminal required for support (after initial setup)
