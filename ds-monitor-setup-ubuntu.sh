#!/bin/bash
set -Euo pipefail
# Le azioni del menu vengono eseguite in un processo Bash con arresto su errore.

TARGET_USER="monitor"
TARGET_PASS="monitor"
VNC_PASS="monitor"
DEFAULT_HOSTNAME="ds-monitor"

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Esegui come root: sudo bash $0"
    exit 1
  fi
}

backup_file() {
  local f="$1" dest
  if [[ -e "$f" || -L "$f" ]]; then
    dest="$(mktemp -d /var/backups/ds-monitor-file.XXXXXXXX)"
    cp -a -- "$f" "$dest/"
    echo "Backup: $dest" >&2
  fi
}

ensure_user_home() {
  id "$TARGET_USER" >/dev/null 2>&1 || { echo "Utente $TARGET_USER non trovato." >&2; return 1; }
  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  [[ "$TARGET_HOME" == /* && "$TARGET_HOME" != / && -d "$TARGET_HOME" ]] || return 1
  install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$TARGET_HOME/.config/autostart" "$TARGET_HOME/.config/conky"
}

valid_hostname() {
  [[ ${#1} -le 63 && "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]
}

valid_ipv4() {
  local part
  local -a parts
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a parts <<< "$1"
  for part in "${parts[@]}"; do (( 10#$part <= 255 )) || return 1; done
}

run_action() {
  local result=0
  bash "${BASH_SOURCE[0]}" --run-action "$@" || result=$?
  if (( result != 0 )); then
    echo "Operazione non completata (codice $result). Controllare gli errori sopra." >&2
  fi
  return 0
}

pause_screen() {
  echo
  read -rp "Premi Invio per continuare..." _
}

get_main_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_ethernet_iface() {
  local iface
  iface=$(ip -o link show | awk -F': ' '$2 ~ /^(en|eth)/ && !found {split($2, name, "@"); print name[1]; found=1}')
  if [ -n "$iface" ]; then
    echo "$iface"
  else
    get_main_iface
  fi
}

mask_to_cidr() {
  case "$1" in
    255.255.255.255) echo 32 ;;
    255.255.255.254) echo 31 ;;
    255.255.255.252) echo 30 ;;
    255.255.255.248) echo 29 ;;
    255.255.255.240) echo 28 ;;
    255.255.255.224) echo 27 ;;
    255.255.255.192) echo 26 ;;
    255.255.255.128) echo 25 ;;
    255.255.255.0) echo 24 ;;
    255.255.254.0) echo 23 ;;
    255.255.252.0) echo 22 ;;
    255.255.248.0) echo 21 ;;
    255.255.240.0) echo 20 ;;
    255.255.224.0) echo 19 ;;
    255.255.192.0) echo 18 ;;
    255.255.128.0) echo 17 ;;
    255.255.0.0) echo 16 ;;
    255.254.0.0) echo 15 ;;
    255.252.0.0) echo 14 ;;
    255.248.0.0) echo 13 ;;
    255.240.0.0) echo 12 ;;
    255.224.0.0) echo 11 ;;
    255.192.0.0) echo 10 ;;
    255.128.0.0) echo 9 ;;
    255.0.0.0) echo 8 ;;
    0.0.0.0) echo 0 ;;
    *) return 1 ;;
  esac
}

fix_netplan_permissions() {
  if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    chmod 600 /etc/netplan/*.yaml 2>/dev/null || true
    chown root:root /etc/netplan/*.yaml 2>/dev/null || true
  fi
}

apply_netplan() {
  fix_netplan_permissions
  netplan generate
  echo "Conferma la rete entro 120 secondi; Netplan tenta il ripristino se non confermata."
  netplan try --timeout 120
}

configure_network() (
  # Ripristina anche il file persistente se generazione o conferma falliscono.
  set -Eeuo pipefail
  local mode="$1" saved existed=no completed=no
  shift
  saved=$(mktemp -d /var/backups/ds-monitor-netplan.XXXXXXXX)
  if [[ -e /etc/netplan/99-ds-monitor.yaml ]]; then
    cp -a /etc/netplan/99-ds-monitor.yaml "$saved/99-ds-monitor.yaml"
    existed=yes
  fi
  trap 'if [[ "$completed" != yes ]]; then
    if [[ "$existed" == yes ]]; then
      cp -a "$saved/99-ds-monitor.yaml" /etc/netplan/99-ds-monitor.yaml
    else
      rm -f /etc/netplan/99-ds-monitor.yaml
    fi
    netplan generate || true
    echo "Configurazione persistente ripristinata. Controllare la connettivita dalla console." >&2
  fi' EXIT
  case "$mode" in
    static) write_netplan_static "$@" ;;
    dhcp) write_netplan_dhcp "$@" ;;
    *) return 2 ;;
  esac
  chmod 600 /etc/netplan/99-ds-monitor.yaml
  apply_netplan
  completed=yes
  echo "Backup rete: $saved"
)

create_monitor_user() {
  echo "Creo/configuro utente $TARGET_USER..."
  local USER_CREATED=no
  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    USER_CREATED=yes
    useradd -m -s /bin/bash "$TARGET_USER"
  fi
  if [[ "$USER_CREATED" == yes ]]; then
    echo "$TARGET_USER:$TARGET_PASS" | chpasswd
  fi
  usermod -aG sudo "$TARGET_USER" || true
  ensure_user_home
  echo "Utente configurato. Password degli utenti esistenti conservata."
}

update_system_index() {
  apt update
}

update_full_system() {
  echo "Aggiornamento sistema in corso..."
  apt update
  # APT mostra il piano e chiede conferma; la pulizia resta nel menu manutenzione.
  apt full-upgrade
  echo "Aggiornamento completato."
  echo
  read -rp "Riavviare il sistema? (s/n): " R
  if [[ "$R" == "s" || "$R" == "S" ]]; then
    reboot
  fi
}

install_base_tools() {
  apt install -y curl wget gnupg ca-certificates software-properties-common net-tools unzip openssl xdotool x11-xserver-utils
}

update_system_drivers() {
  echo "Aggiornamento driver di sistema..."
  apt update
  if ! command -v ubuntu-drivers >/dev/null 2>&1; then
    apt install -y ubuntu-drivers-common
  fi
  echo
  echo "Driver disponibili:"
  ubuntu-drivers list || true
  echo
  local confirm
  read -rp "Installare i driver consigliati elencati? [s/N]: " confirm
  [[ "$confirm" == s || "$confirm" == S ]] || return 0
  ubuntu-drivers install
  echo "Aggiornamento driver completato. Riavvio consigliato."
}

manual_software_updates() {
  local choice package confirm
  echo '===== AGGIORNAMENTI SOFTWARE MANUALI ====='
  echo '1 - Cerca aggiornamenti APT (senza installare)'
  echo '2 - Aggiorna pacchetti APT (upgrade con conferma)'
  echo '3 - Scarica soltanto aggiornamenti APT'
  echo '4 - Aggiorna un pacchetto APT specifico'
  echo '5 - Cerca aggiornamenti Snap'
  echo '6 - Aggiorna una app Snap specifica'
  echo '7 - Aggiorna app Flatpak di sistema (con conferma)'
  echo '0 - Annulla'
  read -rp 'Scelta: ' choice
  case "$choice" in
    1) apt update; apt list --upgradable ;;
    2) apt update; apt upgrade ;;
    3) apt update; apt-get --download-only upgrade ;;
    4)
      read -rp 'Nome pacchetto APT: ' package
      [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?$ ]] || return 1
      apt update
      apt install --only-upgrade "$package"
      ;;
    5) command -v snap >/dev/null || { echo 'Snap non installato.'; return 1; }; snap refresh --list ;;
    6)
      command -v snap >/dev/null || { echo 'Snap non installato.'; return 1; }
      snap list
      read -rp 'Nome app Snap da aggiornare: ' package
      [[ "$package" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
      read -rp "Scaricare e aggiornare $package ora? [s/N]: " confirm
      [[ "$confirm" == s || "$confirm" == S ]] || return 0
      snap refresh "$package"
      ;;
    7) command -v flatpak >/dev/null || { echo 'Flatpak non installato.'; return 1; }; flatpak --system update ;;
    0) return 0 ;;
    *) echo 'Scelta non valida.'; return 1 ;;
  esac
}

firmware_command() {
  local result=0
  fwupdmgr "$@" || result=$?
  # fwupd: 2 indica esecuzione riuscita senza operazioni disponibili.
  if (( result == 2 )); then
    echo 'Nessuna operazione firmware disponibile.'
    return 0
  fi
  return "$result"
}

prepare_manual_firmware() {
  command -v fwupdmgr >/dev/null || { echo 'Installa prima il supporto firmware (voce 1).'; return 1; }
  # Migrazione dal vecchio blocco: il daemon e il completamento offline devono
  # essere disponibili per gli aggiornamenti richiesti dall'amministratore.
  # I timer e il servizio di ricerca automatica restano nello stato corrente.
  local unit state
  for unit in fwupd.service fwupd-offline-update.service; do
    state=$(systemctl show "$unit" -p LoadState --value) || return 1
    if [[ "$state" == masked ]]; then
      systemctl unmask "$unit" || return 1
      systemctl --runtime unmask "$unit" || return 1
    fi
  done
  systemctl daemon-reload || return 1
  systemctl start fwupd.service
}

manual_firmware_updates() {
  local choice device archive confirm
  echo '===== FIRMWARE MANUALE (fwupd / LVFS) ====='
  echo '1 - Installa il supporto firmware fwupd'
  echo '2 - Mostra dispositivi e versioni firmware'
  echo '3 - Cerca firmware disponibili (scarica solo il catalogo)'
  echo '4 - Scarica e installa firmware per un dispositivo o tutti'
  echo '5 - Installa un firmware da file locale .cab'
  echo '6 - Mostra storico aggiornamenti firmware'
  echo '0 - Annulla'
  echo 'Disponibilita firmware dipendente dal supporto del produttore.'
  read -rp 'Scelta: ' choice
  case "$choice" in
    0) return 0 ;;
    1) apt update; apt install fwupd; return ;;
    2|3|4|5|6) prepare_manual_firmware ;;
    *) echo 'Scelta non valida.'; return 1 ;;
  esac
  case "$choice" in
    2) firmware_command get-devices ;;
    3) firmware_command refresh; firmware_command get-updates ;;
    4)
      firmware_command refresh
      firmware_command get-updates
      read -rp 'ID dispositivo, oppure TUTTI (Invio annulla): ' device
      [[ -n "$device" ]] || return 0
      [[ "$device" == TUTTI || "$device" =~ ^[a-fA-F0-9-]+$ ]] || { echo 'ID non valido.'; return 1; }
      echo 'Non interrompere alimentazione o installazione. fwupd chiede conferma per eventuale riavvio.'
      read -rp 'Scaricare e installare adesso il firmware selezionato? [s/N]: ' confirm
      [[ "$confirm" == s || "$confirm" == S ]] || return 0
      if [[ "$device" == TUTTI ]]; then
        firmware_command update
      else
        firmware_command update "$device"
      fi
      ;;
    5)
      read -rp 'Percorso assoluto del file .cab del produttore: ' archive
      [[ "$archive" == /*.cab && -f "$archive" ]] || { echo 'File .cab non valido.'; return 1; }
      firmware_command get-details "$archive"
      read -rp 'Installare questo firmware? [s/N]: ' confirm
      [[ "$confirm" == s || "$confirm" == S ]] || return 0
      firmware_command install "$archive"
      ;;
    6) firmware_command get-history ;;
  esac
}

disable_wayland() {
  local f=/etc/gdm3/custom.conf
  [ -f "$f" ] || { echo "GDM non trovato."; return 1; }
  backup_file "$f"
  grep -q '^\[daemon\]' "$f" || sed -i '1i[daemon]' "$f"
  if grep -q '^WaylandEnable=' "$f"; then
    sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$f"
  else
    sed -i '/^\[daemon\]/a WaylandEnable=false' "$f"
  fi
  echo "Wayland disabilitato. Riavvio consigliato."
}

enable_auto_login() {
  local f=/etc/gdm3/custom.conf
  mkdir -p /etc/gdm3
  id "$TARGET_USER" >/dev/null 2>&1 || return 1
  [ -f "$f" ] || printf '[daemon]\n' > "$f"
  backup_file "$f"
  grep -q '^\[daemon\]' "$f" || sed -i '1i[daemon]' "$f"

  if grep -q '^AutomaticLoginEnable=' "$f"; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' "$f"
  else
    sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' "$f"
  fi

  if grep -q '^AutomaticLogin=' "$f"; then
    sed -i "s/^AutomaticLogin=.*/AutomaticLogin=$TARGET_USER/" "$f"
  else
    sed -i "/^\[daemon\]/a AutomaticLogin=$TARGET_USER" "$f"
  fi

  if grep -q '^WaylandEnable=' "$f"; then
    sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$f"
  else
    sed -i '/^\[daemon\]/a WaylandEnable=false' "$f"
  fi

  echo "Auto-login abilitato per $TARGET_USER"
}

check_auto_login() {
  local f=/etc/gdm3/custom.conf
  echo "Controllo auto-login..."
  if [ ! -f "$f" ]; then
    echo "File $f non trovato."
    return 1
  fi
  local enabled loginuser
  enabled=$(grep -E '^AutomaticLoginEnable=' "$f" | tail -n1 | cut -d= -f2)
  loginuser=$(grep -E '^AutomaticLogin=' "$f" | tail -n1 | cut -d= -f2)
  echo "AutomaticLoginEnable=${enabled:-non impostato}"
  echo "AutomaticLogin=${loginuser:-non impostato}"
  if [ "$enabled" = "true" ] && [ "$loginuser" = "$TARGET_USER" ]; then
    echo "Esito: auto-login configurato correttamente per $TARGET_USER"
    return 0
  fi
  echo "Esito: auto-login NON configurato correttamente"
  return 1
}

disable_all_power_management() {
  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Utente $TARGET_USER non trovato."
    return 1
  fi

  echo "Configurazione modalità ALWAYS ON sicura..."
  ensure_user_home

  # Auto-login e Wayland OFF
  enable_auto_login || true
  disable_wayland || true

  # Script eseguito DOPO il login grafico.
  # Non riavvia systemd-logind, così evita il blocco immediato della sessione.
  cat > /usr/local/bin/ds-monitor-disable-power.sh <<EOF2
#!/bin/bash
sleep 10

UID_NUM=\$(id -u $TARGET_USER)
export DISPLAY=:0
export XAUTHORITY="$TARGET_HOME/.Xauthority"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$UID_NUM/bus"

xset s off || true
xset -dpms || true
xset s noblank || true

gsettings set org.gnome.desktop.session idle-delay 0 || true
gsettings set org.gnome.desktop.screensaver lock-enabled false || true
gsettings set org.gnome.desktop.lockdown disable-lock-screen true || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || true
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing' || true
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false || true
gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false || true
EOF2

  chmod +x /usr/local/bin/ds-monitor-disable-power.sh

  mkdir -p "$TARGET_HOME/.config/autostart"

  cat > "$TARGET_HOME/.config/autostart/ds-monitor-disable-power.desktop" <<EOF2
[Desktop Entry]
Type=Application
Name=DS Monitor Always On
Exec=/usr/local/bin/ds-monitor-disable-power.sh
X-GNOME-Autostart-enabled=true
Terminal=false
EOF2

  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart"

  mkdir -p /etc/systemd/logind.conf.d
  cat > /etc/systemd/logind.conf.d/ds-monitor.conf <<EOF2
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
IdleActionSec=0
EOF2

  mkdir -p /etc/systemd/sleep.conf.d
  cat > /etc/systemd/sleep.conf.d/ds-monitor.conf <<EOF2
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
EOF2

  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
  systemctl daemon-reload || true

  echo "OK: modalità ALWAYS ON configurata."
  echo "Riavvia il PC per applicare tutto correttamente."
}

check_power_saving_status() {
  ensure_user_home
  echo "===== CHECK RISPARMIO ENERGIA ====="
  echo "Autostart:"
  [ -f "$TARGET_HOME/.config/autostart/ds-monitor-disable-power.desktop" ] && echo "power script: ok" || echo "power script: mancante"
  [ -f "$TARGET_HOME/.config/autostart/ds-monitor-screenoff.desktop" ] && echo "screenoff script: ok" || echo "screenoff script: mancante"
  echo
  echo "logind:"
  [ -f /etc/systemd/logind.conf.d/ds-monitor.conf ] && cat /etc/systemd/logind.conf.d/ds-monitor.conf || echo "config logind mancante"
  echo
  echo "sleep.conf:"
  [ -f /etc/systemd/sleep.conf.d/ds-monitor.conf ] && cat /etc/systemd/sleep.conf.d/ds-monitor.conf || echo "config sleep mancante"
  echo
  echo "target:"
  systemctl is-enabled sleep.target 2>/dev/null || true
  systemctl is-enabled suspend.target 2>/dev/null || true
  systemctl is-enabled hibernate.target 2>/dev/null || true
  systemctl is-enabled hybrid-sleep.target 2>/dev/null || true
}

set_pc_hostname() {
  read -rp "Nuovo hostname: " NEW_HOSTNAME
  valid_hostname "$NEW_HOSTNAME" || { echo "Hostname non valido."; return 1; }
  hostnamectl set-hostname "$NEW_HOSTNAME"
  backup_file /etc/hosts
  if grep -q '^127.0.1.1' /etc/hosts 2>/dev/null; then
    sed -i "s/^127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
  else
    echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
  fi
  echo "Hostname impostato a $NEW_HOSTNAME"
}

reset_pc_hostname() {
  hostnamectl set-hostname "$DEFAULT_HOSTNAME"
  backup_file /etc/hosts
  if grep -q '^127.0.1.1' /etc/hosts 2>/dev/null; then
    sed -i "s/^127.0.1.1.*/127.0.1.1\t$DEFAULT_HOSTNAME/" /etc/hosts
  else
    echo -e "127.0.1.1\t$DEFAULT_HOSTNAME" >> /etc/hosts
  fi
  echo "Hostname resettato a $DEFAULT_HOSTNAME"
}

write_netplan_static() {
  local iface="$1" ipaddr="$2" cidr="$3" gw="$4" dns1="$5" dns2="$6"
  local dns_line
  if [ -n "$dns2" ]; then
    dns_line="$dns1, $dns2"
  else
    dns_line="$dns1"
  fi
  cat > /etc/netplan/99-ds-monitor.yaml <<EOF2
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $iface:
      dhcp4: false
      addresses:
        - $ipaddr/$cidr
      routes:
        - to: default
          via: $gw
      nameservers:
        addresses: [$dns_line]
EOF2
}

write_netplan_dhcp() {
  local iface="$1"
  cat > /etc/netplan/99-ds-monitor.yaml <<EOF2
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $iface:
      dhcp4: true
EOF2
}

change_static_ip() {
  local IFACE NETMASK CIDR IPADDR GATEWAY DNS1 DNS2
  IFACE=$(get_ethernet_iface)
  echo "Scheda ethernet rilevata: $IFACE"
  [ -z "$IFACE" ] && { echo "Scheda ethernet non trovata."; return 1; }

  read -rp "IP: " IPADDR
  read -rp "Subnet mask (es. 255.255.255.0): " NETMASK
  read -rp "Gateway: " GATEWAY
  read -rp "DNS1 [1.1.1.1]: " DNS1; DNS1=${DNS1:-1.1.1.1}
  read -rp "DNS2 [8.8.8.8]: " DNS2; DNS2=${DNS2:-8.8.8.8}

  [ -z "$IPADDR" ] || [ -z "$NETMASK" ] || [ -z "$GATEWAY" ] && { echo "Parametri non validi."; return 1; }
  local value
  for value in "$IPADDR" "$GATEWAY" "$DNS1" "$DNS2"; do
    valid_ipv4 "$value" || { echo "IPv4 non valido: $value"; return 1; }
  done
  [[ "$IFACE" =~ ^[a-zA-Z0-9_.:-]+$ ]] || return 1
  CIDR=$(mask_to_cidr "$NETMASK") || { echo "Subnet mask non valida."; return 1; }

  configure_network static "$IFACE" "$IPADDR" "$CIDR" "$GATEWAY" "$DNS1" "$DNS2"
  echo "IP statico configurato."
}

set_dhcp_network() {
  local IFACE
  IFACE=$(get_ethernet_iface)
  echo "Scheda ethernet rilevata: $IFACE"
  [ -z "$IFACE" ] && { echo "Interfaccia non valida."; return 1; }
  configure_network dhcp "$IFACE"
  echo "DHCP attivato."
}

show_network_config() {
  echo "Hostname: $(hostname)"
  echo "IP: $(hostname -I 2>/dev/null)"
  echo "Route:"
  ip route || true
  echo
  if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    ls -l /etc/netplan/
    echo
    for f in /etc/netplan/*.yaml; do
      [ -f "$f" ] && echo "----- $f -----" && cat "$f"
    done
  else
    echo "Netplan custom non presente."
  fi
}

install_ssh() {
  apt install -y openssh-server
  systemctl enable ssh
  systemctl restart ssh
  echo "SSH installato."
}

install_vnc() {
  ensure_user_home
  apt install -y x11vnc
  disable_wayland
  install -d -m 755 /etc/x11vnc
  if [[ ! -f /etc/x11vnc/passwd ]]; then
    x11vnc -storepasswd "$VNC_PASS" /etc/x11vnc/passwd
  fi
  chown "$TARGET_USER:$(id -gn "$TARGET_USER")" /etc/x11vnc/passwd
  chmod 600 /etc/x11vnc/passwd
  write_vnc_service 5900
  echo 'VNC configurato sulla porta 5900. Serve una sessione X11 attiva; riavvia dopo la disabilitazione di Wayland.'
}


configure_vnc_port() {
  local port
  read -rp 'Porta VNC [5900]: ' port
  port=${port:-5900}
  [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1024 && 10#$port <= 65535 )) || { echo 'Porta valida: 1024-65535.'; return 1; }
  command -v x11vnc >/dev/null && [[ -f /etc/x11vnc/passwd ]] || { echo 'Installa prima VNC.'; return 1; }
  write_vnc_service "$((10#$port))"
}

write_vnc_service() {
  local port="$1" old_port=''
  ensure_user_home
  [[ ! -f /etc/x11vnc/port ]] || read -r old_port < /etc/x11vnc/port
  backup_file /etc/systemd/system/x11vnc.service
  cat > /etc/systemd/system/x11vnc.service <<EOF
[Unit]
Description=DS Monitor x11vnc
After=display-manager.service network.target
Requires=display-manager.service
[Service]
Type=simple
User=$TARGET_USER
Environment=DISPLAY=:0
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -rfbport $port -forever -shared -rfbauth /etc/x11vnc/passwd
Restart=on-failure
RestartSec=5
[Install]
WantedBy=graphical.target
EOF
  printf '%s\n' "$port" > /etc/x11vnc/port
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$port/tcp"
    if [[ "$old_port" =~ ^[0-9]+$ && "$old_port" != "$port" ]]; then
      ufw delete allow "$old_port/tcp"
    fi
  fi
  systemctl daemon-reload
  systemctl enable x11vnc.service
  systemctl restart x11vnc.service
  systemctl --no-pager status x11vnc.service
}

show_vnc_ports() {
  echo "===== PORTE VNC ====="
  echo "Servizio x11vnc:"
  systemctl is-active x11vnc 2>/dev/null || true
  echo
  echo "Porte VNC in ascolto:"
  ss -tulnp | grep -E ':(5900|5901|5902|5903|5904|5905)' || echo "Nessuna porta VNC standard in ascolto."
  echo
  echo "Regole firewall VNC:"
  ufw status numbered 2>/dev/null | grep -E '5900|5901|5902|5903|5904|5905' || echo "Nessuna regola VNC trovata in UFW."
}

uninstall_vnc() {
  echo "Disinstallazione VNC..."

  systemctl stop x11vnc.service 2>/dev/null || true
  systemctl disable x11vnc.service 2>/dev/null || true
  rm -f /etc/systemd/system/x11vnc.service
  systemctl daemon-reload || true

  # Arresta soltanto il servizio gestito da questo script.

  local old_port=5900
  [[ ! -f /etc/x11vnc/port ]] || read -r old_port < /etc/x11vnc/port
  rm -f /etc/x11vnc/passwd /etc/x11vnc/port
  rmdir /etc/x11vnc 2>/dev/null || true
  rm -f /etc/x11vnc.pass

  if command -v ufw >/dev/null 2>&1; then
    if [[ "$old_port" =~ ^[0-9]{1,5}$ ]]; then
      ufw delete allow "$old_port/tcp"
    fi
    ufw reload 2>/dev/null || true
  fi

  apt purge -y x11vnc || true
  apt autoremove -y || true

  echo "VNC disinstallato."
}

uninstall_livecare_agent() {
  local version
  version=$(sed -n 's/^VERSION_ID="\(.*\)"/\1/p' /etc/os-release)
  [[ "$version" == 22.04 ]] || { echo 'Repository Livecare fornito per Ubuntu 22.04: verificare con il produttore per questa versione.' >&2; return 1; }
  apt install -y curl gnupg ca-certificates
  install -d -m 755 /etc/apt/keyrings
  local key_file
  key_file=$(mktemp)
  if ! curl -fsSL --max-time 60 https://cdn.livecare.net/linux/livecare/xUbuntu_22.04/Release.key -o "$key_file"; then
    rm -f "$key_file"; return 1
  fi
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/livecare.gpg "$key_file"
  rm -f "$key_file"
  chmod 644 /etc/apt/keyrings/livecare.gpg
  backup_file /etc/apt/sources.list.d/livecare.list
  echo 'deb [signed-by=/etc/apt/keyrings/livecare.gpg] https://cdn.livecare.net/linux/livecare/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/livecare.list
  apt update
  apt install -y livecare-agent
}

install_livecare_agent() {
  echo "Installo Livecare Agent (repo xUbuntu_22.04)..."
  echo "deb https://cdn.livecare.net/linux/livecare/xUbuntu_22.04/ /" > /etc/apt/sources.list.d/livecare.list
  curl -fsSL https://cdn.livecare.net/linux/livecare/xUbuntu_22.04/Release.key | gpg --dearmor > /etc/apt/trusted.gpg.d/livecare.gpg
  apt update
  apt install -y livecare-agent
}

verify_remote_services() {
  echo "SSH: $(systemctl is-active ssh 2>/dev/null || true)"
  echo "VNC: $(systemctl is-active x11vnc 2>/dev/null || true)"
  dpkg -l | grep -q livecare-agent && echo "Livecare: installato" || echo "Livecare: non trovato"
}

install_chromium() { apt install -y chromium-browser || snap install chromium; }
install_firefox() { apt install -y firefox || snap install firefox; }

configure_kiosk() {
  id "$TARGET_USER" >/dev/null 2>&1 || { echo "Utente $TARGET_USER non trovato."; return 1; }
  ensure_user_home
  read -rp "URL kiosk: " URL
  [[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || { echo "URL HTTP/HTTPS non valido."; return 1; }
  local URL_SHELL BROWSER_SHELL
  printf -v URL_SHELL '%q' "$URL"
  read -rp "Browser [chromium/firefox]: " BROWSER

  case "$BROWSER" in
    chromium|Chromium|chrome|Chrome)
      BROWSER_EXEC=$(command -v chromium-browser || command -v chromium || command -v google-chrome || true)
      [ -z "$BROWSER_EXEC" ] && { echo "Chromium/Chrome non trovato."; return 1; }
      printf -v BROWSER_SHELL '%q' "$BROWSER_EXEC"
      BROWSER_NAME="chromium"

      cat > /usr/local/bin/ds-monitor-kiosk.sh <<EOF2
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY="$TARGET_HOME/.Xauthority"
sleep 20
pkill -u "$TARGET_USER" -x chromium || true
pkill -u "$TARGET_USER" -x chrome || true
exec $BROWSER_SHELL --kiosk --no-first-run --incognito $URL_SHELL
EOF2
      ;;
    firefox|Firefox)
      BROWSER_EXEC=$(command -v firefox || true)
      [ -z "$BROWSER_EXEC" ] && { echo "Firefox non trovato."; return 1; }
      printf -v BROWSER_SHELL '%q' "$BROWSER_EXEC"
      BROWSER_NAME="firefox"

      cat > /usr/local/bin/ds-monitor-kiosk.sh <<EOF2
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY="$TARGET_HOME/.Xauthority"
sleep 20
pkill -u "$TARGET_USER" -x firefox || true
exec $BROWSER_SHELL --kiosk $URL_SHELL
EOF2
      ;;
    *)
      echo "Browser non valido."
      return 1
      ;;
  esac

  chmod +x /usr/local/bin/ds-monitor-kiosk.sh

  cat > "$TARGET_HOME/.config/autostart/ds-monitor-kiosk.desktop" <<EOF2
[Desktop Entry]
Type=Application
Name=DS Monitor Kiosk
Exec=/usr/local/bin/ds-monitor-kiosk.sh
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
Terminal=false
EOF2

  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/ds-monitor-kiosk.desktop"

  cat > /etc/ds-monitor-kiosk.conf <<EOF2
URL=$URL
BROWSER=$BROWSER_NAME
MODE=kiosk
AUTO_RESTART=no
EOF2

  echo "Kiosk configurato."
}

install_conky_ip_overlay() {
  id "$TARGET_USER" >/dev/null 2>&1 || { echo "Utente $TARGET_USER non trovato."; return 1; }
  ensure_user_home
  apt install -y conky-all || apt install -y conky
  cat > "$TARGET_HOME/.config/conky/conky-ip.conf" <<'EOF2'
conky.config = {
    alignment = 'bottom_right',
    background = true,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    double_buffer = true,
    use_xft = true,
    font = 'DejaVu Sans Mono:size=11',
    update_interval = 5,
    minimum_width = 340,
    minimum_height = 90,
    draw_borders = false,
    border_width = 0,
    default_color = 'white',
    no_buffers = true,
};

conky.text = [[
Host: ${nodename}
IP Locale: ${exec hostname -I | awk '{print $1}'}
IP Pubblico: ${execi 60 curl -fsS --max-time 10 https://ifconfig.me || echo N/D}
Ora: ${time %d-%m-%Y %H:%M:%S}
]];
EOF2
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/conky"
  cat > /usr/local/bin/ds-monitor-conky.sh <<EOF2
#!/bin/bash
sleep 8
pkill -u "$TARGET_USER" -f "conky.*conky-ip.conf" || true
sudo -u "$TARGET_USER" DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" conky -c "$TARGET_HOME/.config/conky/conky-ip.conf" &
EOF2
  chmod +x /usr/local/bin/ds-monitor-conky.sh
  cat > "$TARGET_HOME/.config/autostart/ds-monitor-conky.desktop" <<EOF2
[Desktop Entry]
Type=Application
Name=DS Monitor Conky
Exec=/usr/local/bin/ds-monitor-conky.sh
X-GNOME-Autostart-enabled=true
Terminal=false
EOF2
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/ds-monitor-conky.desktop"
  echo "Overlay IP configurato."
}

show_kiosk_config() {
  [ -f /etc/ds-monitor-kiosk.conf ] && cat /etc/ds-monitor-kiosk.conf || echo "Config kiosk non presente."
}

fix_network_gui() {
  echo "Ripristino gestione rete tramite NetworkManager..."
  if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    for f in /etc/netplan/*.yaml; do
      [ -f "$f" ] || continue
      backup_file "$f"
      sed -i 's/renderer:[[:space:]]*networkd/renderer: NetworkManager/g' "$f"
      chmod 600 "$f" || true
      chown root:root "$f" || true
    done
  fi
  apply_netplan
  echo "Fix GUI rete completato."
}

start_kiosk_now() {
  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Utente $TARGET_USER non trovato."
    return 1
  fi
  if [ ! -x /usr/local/bin/ds-monitor-kiosk.sh ]; then
    echo "Script kiosk non trovato. Configura prima il kiosk."
    return 1
  fi
  ensure_user_home
  sudo -u "$TARGET_USER" DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" /usr/local/bin/ds-monitor-kiosk.sh >/dev/null 2>&1 &
  echo "Avvio manuale kiosk eseguito."
}

install_java() { apt install -y default-jre; }

show_diagnostics() {
  echo "Hostname: $(hostname)"
  echo "IP locale: $(hostname -I 2>/dev/null)"
  echo "IP pubblico: $(curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null || echo N/D)"
  echo "Machine-id: $(cat /etc/machine-id 2>/dev/null || echo N/D)"
  echo "SSH: $(systemctl is-active ssh 2>/dev/null || true)"
  echo "VNC: $(systemctl is-active x11vnc 2>/dev/null || true)"
  command -v chromium-browser >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 && echo "Chromium: ok" || echo "Chromium: no"
  command -v firefox >/dev/null 2>&1 && echo "Firefox: ok" || echo "Firefox: no"
  dpkg -l | grep -q livecare-agent && echo "Livecare: ok" || echo "Livecare: no"
  check_auto_login || true
  show_kiosk_config
}

prepare_for_clone() {
  reset_pc_hostname
  local IFACE
  IFACE=$(get_ethernet_iface)
  if [[ -n "$IFACE" ]]; then
    configure_network dhcp "$IFACE"
  fi
  echo "Macchina pronta per clonazione."
}

reset_network_identity() {
  # Genera un ID nuovo: systemd-machine-id-setup puo' riutilizzare il vecchio ID D-Bus.
  local machine_id
  machine_id=$(systemd-id128 new)
  [[ "$machine_id" =~ ^[0-9a-f]{32}$ ]] || return 1
  backup_file /etc/machine-id
  printf '%s\n' "$machine_id" > /etc/machine-id
  if [[ -e /var/lib/dbus/machine-id || -L /var/lib/dbus/machine-id ]]; then
    backup_file /var/lib/dbus/machine-id
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
  fi
  echo "Identita persistente rigenerata; riavvio necessario."
}

regenerate_ssh_host_keys() {
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A
  systemctl restart ssh || true
  echo "Chiavi host SSH rigenerate."
}

post_clone_setup() {
  read -rp "Numero macchina (es. 01): " NUM
  [[ "$NUM" =~ ^[0-9]{1,4}$ ]] || { echo "Numero non valido."; return 1; }
  printf -v NUM "%02d" "$((10#$NUM))"
  reset_network_identity
  regenerate_ssh_host_keys
  NEW_HOSTNAME="ds-monitor-$NUM"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  backup_file /etc/hosts
  if grep -q '^127.0.1.1' /etc/hosts 2>/dev/null; then
    sed -i "s/^127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
  else
    echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
  fi
  echo "Post-clone completato per $NEW_HOSTNAME"
}

full_setup() {
  update_full_system
  install_base_tools
  create_monitor_user
  disable_all_power_management
  install_ssh
  install_vnc
  install_chromium
  install_firefox
  install_livecare_agent
  install_java
  install_conky_ip_overlay
  check_auto_login || true
  echo "Setup completo terminato. Configura il kiosk dal menu dedicato."
}

show_system_menu() {
  echo
  echo "===== SISTEMA ====="
  echo "1 - Aggiorna elenco pacchetti"
  echo "2 - Aggiornamento completo sistema"
  echo "3 - Installa pacchetti base"
  echo "4 - Crea utente monitor"
  echo "5 - Aggiornamento driver di sistema"
  echo "6 - Modalità ALWAYS ON"
  echo "7 - Torna indietro"
  echo "8 - Blocca aggiornamenti software e firmware"
  echo "9 - Firmware: cerca, scarica e installa manualmente"
  echo "10 - Aggiorna software / scarica pacchetti"
}

show_network_menu() {
  echo
  echo "===== RETE ====="
  echo "1 - Imposta IP statico"
  echo "2 - Imposta DHCP"
  echo "3 - Cambia hostname"
  echo "4 - Reset hostname"
  echo "5 - Mostra configurazione rete"
  echo "6 - Torna indietro"
}

show_remote_menu() {
  echo
  echo "===== ACCESSO REMOTO ====="
  echo "1 - Installa SSH"
  echo "2 - Installa VNC"
  echo "3 - Installa Livecare Agent"
  echo "4 - Verifica servizi remoti"
  echo "5 - Disinstalla VNC"
  echo "6 - Disinstalla Livecare Agent"
  echo "7 - Torna indietro"
  echo "8 - Configura porta VNC persistente"
}

show_browser_menu() {
  echo
  echo "===== BROWSER E KIOSK ====="
  echo "1 - Installa Chromium"
  echo "2 - Installa Firefox"
  echo "3 - Configura kiosk"
  echo "4 - Avvia manualmente il kiosk"
  echo "5 - Mostra configurazione kiosk"
  echo "6 - Torna indietro"
}



cleanup_temp_files() {

  echo "Pulizia file temporanei in corso..."

  apt autoremove -y
  apt autoclean -y

  journalctl --vacuum-time=7d

  systemd-tmpfiles --clean

  echo
  echo "Pulizia completata."
}

disable_auto_updates() (
set -Eeuo pipefail
[[ -d /etc/apt/apt.conf.d && -d /run/systemd/system ]] || { echo 'Ubuntu con APT e systemd richiesto.' >&2; exit 1; }
umask 077
backup=$(mktemp -d /var/backups/kiosk-updates.XXXXXXXX)
# Il backup resta 0700; profili dconf e autostart devono essere leggibili dagli utenti.
umask 022
declare -A saved_paths=()
systemctl list-unit-files > "$backup/system-units.txt"
systemctl --global list-unit-files > "$backup/user-units.txt"
errors=0
save() {
    local path="$1"
    [[ -z "${saved_paths[$path]:-}" ]] || return 0
    saved_paths[$path]=1
    if [[ -e "$path" || -L "$path" ]]; then
        mkdir -p "$backup$(dirname "$path")"
        cp -a -- "$path" "$backup$path"
    else
        printf '%s\n' "$path" >> "$backup/created-files.txt"
    fi
}
trap 'echo "Errore alla riga $LINENO. Blocco incompleto. Backup: $backup" >&2' ERR

save /etc/apt/apt.conf.d/99zz-disable-auto-updates
cat > /etc/apt/apt.conf.d/99zz-disable-auto-updates <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

mkdir -p /etc/update-manager
save /etc/update-manager/release-upgrades
cat > /etc/update-manager/release-upgrades <<'EOF'
[DEFAULT]
Prompt=never
EOF

# Ferma soltanto i timer; nessuna installazione APT o firmware viene interrotta.
units=(
    apt-daily.timer apt-daily-upgrade.timer
    apt-daily.service apt-daily-upgrade.service unattended-upgrades.service
    packagekit.service packagekit-offline-update.service
    fwupd-refresh.timer fwupd-refresh.service
    systemd-sysupdate.timer systemd-sysupdate.service
    systemd-sysupdate-update.timer systemd-sysupdate-update.service
    flatpak-system-update.timer flatpak-system-update.service
    flatpak-update.timer flatpak-update.service
)
for unit in "${units[@]}"; do
    # Maschera anche unita' attualmente assenti, per bloccarne l'attivazione futura.
    save "/etc/systemd/system/$unit"
    if [[ "$unit" == *.timer ]] && systemctl cat "$unit" >/dev/null 2>&1; then
        systemctl stop "$unit"
    fi
    mask_args=(mask)
    # Non interrompere servizi che potrebbero installare pacchetti o firmware.
    if ! systemctl "${mask_args[@]}" "$unit"; then
        echo "BLOCCO FALLITO: $unit" >&2
        errors=$((errors + 1))
    fi
    # Il timer puo' conservare un errore dopo il blocco: azzeralo.
    if [[ "$(systemctl show "$unit" -p ActiveState --value)" == failed ]]; then
        if ! systemctl reset-failed "$unit"; then
            echo "Impossibile azzerare lo stato di errore: $unit" >&2
            errors=$((errors + 1))
        fi
    fi
done

# Snap: blocca gli aggiornamenti conservando il funzionamento delle app Snap.
if command -v snap >/dev/null 2>&1; then
    snap get system refresh.hold > "$backup/snap-refresh-hold.txt" 2>&1 || true
    snap refresh --time > "$backup/snap-refresh-time.txt" 2>&1 || true
    snap list > "$backup/snap-list.txt" 2>&1 || true
    if ! snap refresh --hold=forever; then
        echo 'BLOCCO SNAP FALLITO: snapd potrebbe essere troppo vecchio.' >&2
        errors=$((errors + 1))
    fi
fi

# Impostazioni GNOME globali bloccate: includono gli aggiornamenti Flatpak
# gestiti da GNOME Software e le notifiche di update-notifier.
if command -v dconf >/dev/null 2>&1; then
    mkdir -p /etc/dconf/profile /etc/dconf/db/local.d/locks
    save /etc/dconf/profile/user
    if [[ ! -e /etc/dconf/profile/user ]]; then
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    elif ! grep -qx 'system-db:local' /etc/dconf/profile/user; then
        printf '\nsystem-db:local\n' >> /etc/dconf/profile/user
    fi
    save /etc/dconf/db/local.d/99-kiosk-updates
    cat > /etc/dconf/db/local.d/99-kiosk-updates <<'EOF'
[org/gnome/software]
allow-updates=false
download-updates=false
download-updates-notify=false

[com/ubuntu/update-notifier]
auto-launch=false
no-show-notifications=true
show-updates-status-icon=false
EOF
    save /etc/dconf/db/local.d/locks/kiosk-updates
    cat > /etc/dconf/db/local.d/locks/kiosk-updates <<'EOF'
/org/gnome/software/allow-updates
/org/gnome/software/download-updates
/org/gnome/software/download-updates-notify
/com/ubuntu/update-notifier/auto-launch
/com/ubuntu/update-notifier/no-show-notifications
/com/ubuntu/update-notifier/show-updates-status-icon
EOF
    chmod 644 /etc/dconf/profile/user /etc/dconf/db/local.d/99-kiosk-updates /etc/dconf/db/local.d/locks/kiosk-updates
    dconf update
elif [[ -d /usr/share/gnome-shell || -d /usr/share/gnome-software ]]; then
    echo "dconf mancante: blocco GNOME incompleto." >&2
    errors=$((errors + 1))
fi

# Disattiva gli avvii automatici dei front-end noti.
# Considera anche nomi diversi dei file .desktop e override nei profili utenti.
mkdir -p /etc/xdg/autostart
names=(update-notifier.desktop update-manager.desktop
       org.gnome.Software.desktop gnome-software-service.desktop
       org.kde.discover.notifier.desktop )
shopt -s nullglob
for entry in /etc/xdg/autostart/*.desktop; do
    if grep -Eq '^Exec=.*(update-notifier|update-manager|gnome-software|discover-notifier)' "$entry"; then
        names+=("${entry##*/}")
    fi
done
hide_entry() {
    local entry="$1"
    if [[ -L "$entry" ]]; then
        echo "Autostart simbolico non modificato: $entry" >&2
        errors=$((errors + 1))
        return 0
    fi
    save "$entry"
    printf '[Desktop Entry]\nType=Application\nName=Kiosk update notifier disabled\nHidden=true\n' > "$entry"
    chmod 644 "$entry"
}
for name in "${names[@]}"; do hide_entry "/etc/xdg/autostart/$name"; done
while IFS=: read -r account _ uid gid _ home _; do
    [[ "$uid" -ge 1000 && "$uid" -lt 65534 && -d "$home" ]] || continue
    [[ -d "$home/.config/autostart" ]] || continue
    for entry in "$home/.config/autostart/"*.desktop; do
        matched=false
        for name in "${names[@]}"; do
            [[ "${entry##*/}" != "$name" ]] || matched=true
        done
        if $matched || grep -Eq '^Exec=.*(update-notifier|update-manager|gnome-software|discover-notifier)' "$entry"; then
            echo "Override utente da controllare: $entry" >&2
            if ! grep -Eq '^Hidden=true[[:space:]]*$' "$entry"; then
                errors=$((errors + 1))
            fi
        fi
    done
done < <(getent passwd)

# Blocca anche GNOME Software attivabile come servizio di sessione.
for unit in org.gnome.Software.service gnome-software.service \
            flatpak-update.timer flatpak-update.service \
            flatpak-user-update.timer flatpak-user-update.service; do
    save "/etc/systemd/user/$unit"
    if ! systemctl --global mask "$unit"; then
        echo "BLOCCO SERVIZIO UTENTE FALLITO: $unit" >&2
        errors=$((errors + 1))
    fi
done
systemctl daemon-reload

# Controlla il risultato effettivo, non solo l'esito dei comandi.
echo '=== Verifica blocchi di sistema ==='
for unit in "${units[@]}"; do
    load_state="$(systemctl show "$unit" -p LoadState --value)"
    active_state="$(systemctl show "$unit" -p ActiveState --value)"
    printf '%s: %s / %s\n' "$unit" "$load_state" "$active_state"
    if [[ "$load_state" != masked ]]; then
        echo "VERIFICA FALLITA: $unit non e' mascherato." >&2
        errors=$((errors + 1))
    fi
    case "$unit" in
        *.timer)
            if [[ "$active_state" != inactive ]]; then
                echo "VERIFICA FALLITA: $unit non e' inattivo." >&2
                errors=$((errors + 1))
            fi
            ;;
        *)
            if [[ "$active_state" != inactive ]]; then
                echo "ATTENZIONE: $unit ha stato $active_state; verificare dopo il riavvio."
            fi
            ;;
    esac
done

echo "Backup configurazioni e stato unita': $backup"
echo 'Riavvia durante la manutenzione, dopo la fine di eventuali installazioni.'
echo 'APT manuale resta disponibile: sudo apt update && sudo apt upgrade'
echo 'Timer/cron personalizzati e updater interni alle app richiedono verifica separata.'
if (( errors > 0 )); then
    echo "ATTENZIONE: $errors blocchi falliti; configurazione NON completa." >&2
    exit 1
fi
echo 'Blocchi configurati. Verificare il kiosk dopo il riavvio.'
check_auto_updates_status
)

check_auto_updates_status() {
  local unit state active errors=0 key value
  echo '===== VERIFICA BLOCCO AGGIORNAMENTI ====='
  for unit in apt-daily.timer apt-daily-upgrade.timer apt-daily.service apt-daily-upgrade.service unattended-upgrades.service packagekit.service packagekit-offline-update.service fwupd-refresh.timer fwupd-refresh.service systemd-sysupdate.timer systemd-sysupdate.service systemd-sysupdate-update.timer systemd-sysupdate-update.service flatpak-system-update.timer flatpak-system-update.service flatpak-update.timer flatpak-update.service; do
    state=$(systemctl show "$unit" -p LoadState --value) || return 1
    active=$(systemctl show "$unit" -p ActiveState --value) || return 1
    printf '%s: %s / %s\n' "$unit" "$state" "$active"
    [[ "$state" == masked ]] || errors=$((errors + 1))
    [[ "$active" == inactive ]] || { echo 'Richiede controllo dopo la fine delle installazioni e il riavvio.'; errors=$((errors + 1)); }
  done
  for key in Enable Update-Package-Lists Download-Upgradeable-Packages Unattended-Upgrade; do
    value=$(apt-config shell RESULT "APT::Periodic::$key") || return 1
    [[ "$value" == "RESULT='0'" ]] || { echo "APT::Periodic::$key non bloccato"; errors=$((errors + 1)); }
  done
  for unit in org.gnome.Software.service gnome-software.service flatpak-update.timer flatpak-update.service flatpak-user-update.timer flatpak-user-update.service; do
    [[ $(readlink "/etc/systemd/user/$unit") == /dev/null ]] || errors=$((errors + 1))
  done
  if command -v snap >/dev/null 2>&1; then
    value=$(LC_ALL=C snap refresh --time) || return 1
    printf '%s\n' "$value"
    grep -Eq '^hold:[[:space:]]+forever$' <<< "$value" || { echo 'Hold Snap permanente non verificato.'; errors=$((errors + 1)); }
  fi
  if (( errors > 0 )); then
    echo "Verifica incompleta: $errors controlli non superati." >&2
    return 1
  fi
  echo 'Blocchi APT, Snap e unita systemd verificati. Le sessioni grafiche richiedono un nuovo login.'
}

show_diag_menu() {
  echo
  echo "===== DIAGNOSTICA / MANUTENZIONE ====="
  echo "1 - Mostra diagnostica completa"
  echo "2 - Controlla auto-login"
  echo "3 - Check risparmio energia"
  echo "4 - Fix rete GUI"
  echo "5 - Installa overlay IP desktop"
  echo "6 - Mostra porte VNC"
  echo "7 - Pulizia file temporanei"
  echo "8 - Blocca aggiornamenti software e firmware"
  echo "9 - Verifica stato aggiornamenti automatici"
  echo "10 - Torna indietro"
}


# ==========================================================
# TEMA AVVIO / WALLPAPER - SISTEMI POS
# ==========================================================

THEME_SCRIPT_TITLE="Tema per logo avvio - Sistemi POS"
THEME_LOGO_FILE="SistemiPOS_logo.png"
THEME_WALLPAPER_FILE="SistemiPos_Wallpaper.jpg"

THEME_BASE_URL="https://www.sistemipos.it/sh"
THEME_LOGO_URL="$THEME_BASE_URL/$THEME_LOGO_FILE"
THEME_WALLPAPER_URL="$THEME_BASE_URL/$THEME_WALLPAPER_FILE"

THEME_NAME="sistemi-pos"
THEME_DISPLAY_NAME="Tema per logo avvio"
THEME_DIR="/usr/share/plymouth/themes/$THEME_NAME"

theme_get_real_user() {
  if id "$TARGET_USER" >/dev/null 2>&1; then
    echo "$TARGET_USER"
  else
    echo "${SUDO_USER:-$USER}"
  fi
}

theme_refresh_paths() {
  THEME_REAL_USER="$(theme_get_real_user)"
  THEME_REAL_HOME="$(getent passwd "$THEME_REAL_USER" | cut -d: -f6)"
  [[ "$THEME_REAL_HOME" == /* && "$THEME_REAL_HOME" != / && -d "$THEME_REAL_HOME" ]] || return 1
  THEME_IMAGES_DIR="$THEME_REAL_HOME/Immagini"

  THEME_LOGO_PATH="$THEME_IMAGES_DIR/$THEME_LOGO_FILE"
  THEME_LOGO_ORIGINAL_PATH="$THEME_IMAGES_DIR/SistemiPOS_logo_originale.png"
  THEME_LOGO_RESIZED_PATH="$THEME_IMAGES_DIR/SistemiPOS_logo_plymouth.png"

  THEME_WALLPAPER_PATH="$THEME_IMAGES_DIR/$THEME_WALLPAPER_FILE"

  THEME_CONFIG_DIR="$THEME_REAL_HOME/.config/sistemi-pos"
  THEME_WALLPAPER_BACKUP_FILE="$THEME_CONFIG_DIR/wallpaper_backup.conf"
}

theme_title() {
  clear
  echo "======================================"
  echo " $THEME_SCRIPT_TITLE"
  echo "======================================"
  echo
}

theme_error() {
  echo
  echo "ERRORE: $1"
}

theme_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

theme_run_as_user() {
  theme_refresh_paths
  sudo -u "$THEME_REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$THEME_REAL_USER")/bus" "$@"
}

theme_prepare_dirs() {
  theme_refresh_paths || return 1
  mkdir -p "$THEME_IMAGES_DIR" "$THEME_CONFIG_DIR"
  chown -R "$THEME_REAL_USER:$THEME_REAL_USER" "$THEME_IMAGES_DIR" "$THEME_CONFIG_DIR" 2>/dev/null || true
}

theme_download_file() {
  local url="$1"
  local dest="$2"

  echo
  echo "Scarico:"
  echo "$url"
  echo
  echo "Salvo in:"
  echo "$dest"
  echo

  if theme_command_exists wget; then
    wget --timeout=30 --tries=2 --user-agent="Mozilla/5.0" -O "$dest" "$url" || return 1
  elif theme_command_exists curl; then
    curl -fL --connect-timeout 15 --max-time 120 -A "Mozilla/5.0" -o "$dest" "$url" || return 1
  else
    theme_error "né wget né curl sono installati. Esegui prima: Installa programmi necessari."
    return 1
  fi

  if [ ! -s "$dest" ]; then
    theme_error "download fallito oppure file vuoto: $dest"
    rm -f "$dest"
    return 1
  fi

  chown "$THEME_REAL_USER:$THEME_REAL_USER" "$dest" 2>/dev/null || true

  echo
  echo "File scaricato correttamente:"
  ls -lh "$dest"
}

theme_install_programs() {
  theme_title
  echo "Installo programmi necessari:"
  echo "- wget"
  echo "- curl"
  echo "- imagemagick"
  echo "- plymouth"
  echo
  apt update
  apt install -y wget curl imagemagick plymouth
  echo
  echo "Programmi installati correttamente."
}

theme_download_images() {
  theme_title
  theme_prepare_dirs

  echo "Scarico logo e sfondo nella cartella Immagini"
  echo
  echo "Cartella:"
  echo "$THEME_IMAGES_DIR"
  echo

  theme_download_file "$THEME_LOGO_URL" "$THEME_LOGO_PATH" || {
    theme_error "non sono riuscito a scaricare il logo."
    echo "Controlla il link:"
    echo "$THEME_LOGO_URL"
    return 1
  }

  theme_download_file "$THEME_WALLPAPER_URL" "$THEME_WALLPAPER_PATH" || {
    theme_error "non sono riuscito a scaricare lo sfondo."
    echo "Controlla il link:"
    echo "$THEME_WALLPAPER_URL"
    return 1
  }

  echo
  echo "Download completato."
  ls -lh "$THEME_LOGO_PATH" "$THEME_WALLPAPER_PATH" 2>/dev/null || true
}

theme_prepare_boot_logo() {
  theme_refresh_paths

  if [ ! -f "$THEME_LOGO_PATH" ]; then
    theme_error "logo non trovato: $THEME_LOGO_PATH"
    echo "Esegui prima: Scarica logo e sfondo."
    return 1
  fi

  echo "Logo trovato:"
  ls -lh "$THEME_LOGO_PATH"
  echo

  echo "Ridimensiono il logo per il tema avvio:"
  echo "- larghezza 500 px"
  echo "- sovrascrivo direttamente $THEME_LOGO_FILE"
  echo

  local TMP_LOGO
  TMP_LOGO="$(mktemp /tmp/sistemi-pos-logo.XXXXXX.png)"

  if theme_command_exists magick; then
    magick "$THEME_LOGO_PATH" -resize 500x "$TMP_LOGO" || { rm -f "$TMP_LOGO"; return 1; }
  elif theme_command_exists convert; then
    convert "$THEME_LOGO_PATH" -resize 500x "$TMP_LOGO" || { rm -f "$TMP_LOGO"; return 1; }
  else
    theme_error "ImageMagick non installato."
    rm -f "$TMP_LOGO"
    return 1
  fi

  mv "$TMP_LOGO" "$THEME_LOGO_PATH"
  chown "$THEME_REAL_USER:$THEME_REAL_USER" "$THEME_LOGO_PATH" 2>/dev/null || true

  echo "Logo ridimensionato:"
  ls -lh "$THEME_LOGO_PATH"
}

theme_create_boot_theme() {
  theme_title
  theme_refresh_paths

  if ! theme_command_exists plymouth; then
    theme_error "Plymouth non risulta installato. Esegui prima: Installa programmi necessari."
    return 1
  fi

  theme_prepare_boot_logo || return 1

  echo
  echo "Creo tema avvio:"
  echo "$THEME_DIR"
  echo

  backup_file "$THEME_DIR"
  mkdir -p "$THEME_DIR"

  cp "$THEME_LOGO_PATH" "$THEME_DIR/$THEME_LOGO_FILE"

  tee "$THEME_DIR/$THEME_NAME.plymouth" > /dev/null <<EOF2
[Plymouth Theme]
Name=$THEME_DISPLAY_NAME
Description=Tema avvio con logo Sistemi POS
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/$THEME_NAME.script
EOF2

  tee "$THEME_DIR/$THEME_NAME.script" > /dev/null <<EOF2
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

logo_image = Image("$THEME_LOGO_FILE");
logo_sprite = Sprite(logo_image);

logo_width = logo_image.GetWidth();
logo_height = logo_image.GetHeight();

logo_sprite.SetX((screen_width - logo_width) / 2);
logo_sprite.SetY((screen_height - logo_height) / 2);
logo_sprite.SetZ(100);
EOF2

  echo "Registro il tema avvio..."
  update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$THEME_DIR/$THEME_NAME.plymouth" 100

  echo "Attivo il tema avvio sistemi-pos..."
  update-alternatives --set default.plymouth "$THEME_DIR/$THEME_NAME.plymouth"

  echo
  echo "Aggiorno initramfs..."
  update-initramfs -u

  echo
  echo "Tema avvio creato e attivato correttamente."
  echo "Per vederlo, riavvia il PC."
}

theme_backup_current_wallpaper() {
  theme_prepare_dirs

  if [ -f "$THEME_WALLPAPER_BACKUP_FILE" ]; then
    return 0
  fi

  if theme_command_exists gsettings; then
    {
      echo "PICTURE_URI=$(theme_run_as_user gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || echo '')"
      echo "PICTURE_URI_DARK=$(theme_run_as_user gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || echo '')"
      echo "PICTURE_OPTIONS=$(theme_run_as_user gsettings get org.gnome.desktop.background picture-options 2>/dev/null || echo '')"
    } > "$THEME_WALLPAPER_BACKUP_FILE"

    chown "$THEME_REAL_USER:$THEME_REAL_USER" "$THEME_WALLPAPER_BACKUP_FILE" 2>/dev/null || true
  fi
}

theme_set_wallpaper() {
  theme_title
  theme_refresh_paths

  if [ ! -f "$THEME_WALLPAPER_PATH" ]; then
    theme_error "wallpaper non trovato: $THEME_WALLPAPER_PATH"
    echo "Esegui prima: Scarica logo e sfondo."
    return 1
  fi

  if ! theme_command_exists gsettings; then
    theme_error "gsettings non trovato. Probabilmente non stai usando GNOME."
    return 1
  fi

  echo "Salvo lo sfondo attuale, se non già salvato..."
  theme_backup_current_wallpaper

  echo
  echo "Imposto il nuovo wallpaper:"
  echo "$THEME_WALLPAPER_PATH"

  local WALLPAPER_URI
  WALLPAPER_URI="file://$THEME_WALLPAPER_PATH"

  # Reset prima di impostare, evita casi in cui GNOME resta su colore pieno/blu.
  theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri || true
  theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri-dark || true

  theme_run_as_user gsettings set org.gnome.desktop.background picture-uri "$WALLPAPER_URI" || return 1
  theme_run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "$WALLPAPER_URI" || true
  theme_run_as_user gsettings set org.gnome.desktop.background picture-options "zoom" || true
  theme_run_as_user gsettings set org.gnome.desktop.background primary-color "#000000" || true
  theme_run_as_user gsettings set org.gnome.desktop.background secondary-color "#000000" || true
  theme_run_as_user gsettings set org.gnome.desktop.background color-shading-type "solid" || true

  echo
  echo "Wallpaper impostato correttamente."
}

theme_restore_boot_theme() {
  theme_title
  echo "Temi avvio disponibili:"
  echo
  update-alternatives --config default.plymouth
  echo
  echo "Aggiorno initramfs..."
  update-initramfs -u
  echo
  echo "Tema avvio ripristinato secondo la tua scelta."
  echo "Di solito per tornare all'originale devi scegliere: 0 oppure bgrt."
}

theme_restore_wallpaper() {
  theme_title
  theme_refresh_paths

  if ! theme_command_exists gsettings; then
    theme_error "gsettings non trovato. Non posso ripristinare automaticamente lo sfondo."
    return 1
  fi

  if [ -f "$THEME_WALLPAPER_BACKUP_FILE" ]; then
    echo "Ripristino il wallpaper salvato prima della modifica..."
    echo "$THEME_WALLPAPER_BACKUP_FILE"
    echo

    local key value PICTURE_URI='' PICTURE_URI_DARK='' PICTURE_OPTIONS=''
    while IFS='=' read -r key value; do
      case "$key" in
        PICTURE_URI) PICTURE_URI="$value" ;;
        PICTURE_URI_DARK) PICTURE_URI_DARK="$value" ;;
        PICTURE_OPTIONS) PICTURE_OPTIONS="$value" ;;
      esac
    done < "$THEME_WALLPAPER_BACKUP_FILE"

    if [ -n "${PICTURE_URI:-}" ]; then
      theme_run_as_user gsettings set org.gnome.desktop.background picture-uri "$PICTURE_URI"
    else
      theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri
    fi

    if [ -n "${PICTURE_URI_DARK:-}" ]; then
      theme_run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "$PICTURE_URI_DARK"
    else
      theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri-dark
    fi

    if [ -n "${PICTURE_OPTIONS:-}" ]; then
      theme_run_as_user gsettings set org.gnome.desktop.background picture-options "$PICTURE_OPTIONS"
    else
      theme_run_as_user gsettings reset org.gnome.desktop.background picture-options
    fi

    echo
    echo "Wallpaper precedente ripristinato."
  else
    echo "Nessun backup wallpaper trovato."
    echo "Ripristino i valori predefiniti di Ubuntu..."

    theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri
    theme_run_as_user gsettings reset org.gnome.desktop.background picture-uri-dark
    theme_run_as_user gsettings reset org.gnome.desktop.background picture-options

    echo
    echo "Wallpaper ripristinato ai valori predefiniti."
  fi
}

theme_show_status() {
  theme_title
  theme_refresh_paths

  echo "Utente rilevato:"
  echo "$THEME_REAL_USER"
  echo
  echo "Home rilevata:"
  echo "$THEME_REAL_HOME"
  echo
  echo "Cartella immagini:"
  echo "$THEME_IMAGES_DIR"
  echo

  echo "Logo:"
  [ -f "$THEME_LOGO_PATH" ] && ls -lh "$THEME_LOGO_PATH" || echo "Non trovato: $THEME_LOGO_PATH"

  echo
  echo "Wallpaper:"
  [ -f "$THEME_WALLPAPER_PATH" ] && ls -lh "$THEME_WALLPAPER_PATH" || echo "Non trovato: $THEME_WALLPAPER_PATH"

  echo
  echo "Backup wallpaper:"
  [ -f "$THEME_WALLPAPER_BACKUP_FILE" ] && echo "$THEME_WALLPAPER_BACKUP_FILE" || echo "Non trovato"

  echo
  echo "Tema avvio attuale:"
  update-alternatives --query default.plymouth 2>/dev/null | grep "Value:" || echo "Non disponibile"

  echo
  echo "Tema avvio Sistemi POS:"
  if [ -d "$THEME_DIR" ]; then
    echo "Presente: $THEME_DIR"
    ls -lh "$THEME_DIR"
  else
    echo "Non presente: $THEME_DIR"
  fi
}

theme_test_boot_theme() {
  theme_title
  echo "Avvio anteprima tema avvio per 5 secondi..."
  echo "Se lo schermo cambia, attendi: verrà chiuso automaticamente."
  echo

  plymouthd || true
  plymouth --show-splash || true
  sleep 5
  plymouth quit || true

  echo
  echo "Test completato."
}

theme_run_all() {
  theme_title
  echo "Eseguirò in sequenza:"
  echo "1. Installazione programmi"
  echo "2. Download logo e sfondo"
  echo "3. Creazione tema avvio con ridimensionamento automatico logo"
  echo "4. Impostazione wallpaper"
  echo

  read -rp "Procedere? [s/N]: " CONFIRM

  if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "Operazione annullata."
    return 0
  fi

  theme_install_programs
  theme_refresh_paths

  theme_download_images || return 1
  theme_refresh_paths

  theme_create_boot_theme
  theme_refresh_paths

  # Piccola pausa di sicurezza: dopo update-initramfs/Plymouth GNOME può essere occupato.
  sleep 2

  if [ ! -f "$THEME_WALLPAPER_PATH" ]; then
    theme_error "wallpaper non trovato dopo il download: $THEME_WALLPAPER_PATH"
    return 1
  fi

  theme_set_wallpaper || return 1

  echo
  echo "Tutto completato."
}

show_theme_menu() {
  echo
  echo "===== GRAFICA ====="
  echo "1 - Installa programmi necessari"
  echo "2 - Scarica logo e sfondo"
  echo "3 - Crea e attiva tema avvio"
  echo "4 - Imposta wallpaper"
  echo "5 - Esegui tutto"
  echo "6 - Mostra stato"
  echo "7 - Test anteprima tema avvio"
  echo "8 - Ripristina tema avvio originale"
  echo "9 - Ripristina wallpaper precedente/predefinito"
  echo "10 - Ripristina tema avvio + wallpaper"
  echo "11 - Torna indietro"
}

show_clone_menu() {
  echo
  echo "===== CLONAZIONE ====="
  echo "1 - Prepara macchina per clonazione"
  echo "2 - Setup post-clone"
  echo "3 - Torna indietro"
}

show_setup_menu() {
  echo
  echo "===== SETUP AUTOMATICO ====="
  echo "1 - Setup completo macchina"
  echo "2 - Torna indietro"
}

show_main_menu() {
  echo
  echo "========================================"
  echo " DS-MONITOR INSTALLER UBUNTU"
  echo "========================================"
  echo "Hostname: $(hostname)"
  echo "1 - Sistema"
  echo "2 - Rete"
  echo "3 - Accesso remoto"
  echo "4 - Browser e kiosk"
  echo "5 - Diagnostica"
  echo "6 - Grafica"
  echo "7 - Clonazione"
  echo "8 - Riavvia sistema"
  echo "9 - Esci"
}

main() {
  need_root
  [[ $(uname -s) == Linux && -d /run/systemd/system && -d /etc/apt ]] || { echo 'Richiesto Linux con systemd e APT.' >&2; return 1; }
  if [[ "${1:-}" == --run-action ]]; then
    [[ $# == 2 && "$2" =~ ^[a-z_]+$ && "$2" != main && "$2" != run_action ]] || return 2
    declare -F "$2" >/dev/null || return 2
    set -Eeuo pipefail
    trap 'echo "Operazione interrotta alla riga $LINENO (codice $?)." >&2' ERR
    "$2"
    return
  fi
  [[ $# == 0 ]] || { echo "Uso: sudo bash $0" >&2; return 2; }

while true; do
  show_main_menu
  read -rp "Scegli categoria: " MAIN_CHOICE || exit 0
  case "$MAIN_CHOICE" in
    1)
      while true; do
        show_system_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action update_system_index; pause_screen ;;
          2) run_action update_full_system; pause_screen ;;
          3) run_action install_base_tools; pause_screen ;;
          4) run_action create_monitor_user; pause_screen ;;
          5) run_action update_system_drivers; pause_screen ;;
          6) run_action disable_all_power_management; pause_screen ;;
          8) run_action disable_auto_updates; pause_screen ;;
          9) run_action manual_firmware_updates; pause_screen ;;
          10) run_action manual_software_updates; pause_screen ;;
          7) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    2)
      while true; do
        show_network_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action change_static_ip; pause_screen ;;
          2) run_action set_dhcp_network; pause_screen ;;
          3) run_action set_pc_hostname; pause_screen ;;
          4) run_action reset_pc_hostname; pause_screen ;;
          5) run_action show_network_config; pause_screen ;;
          6) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    3)
      while true; do
        show_remote_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action install_ssh; pause_screen ;;
          2) run_action install_vnc; pause_screen ;;
          3) run_action install_livecare_agent; pause_screen ;;
          4) run_action verify_remote_services; pause_screen ;;
          5) run_action uninstall_vnc; pause_screen ;;
          6) run_action uninstall_livecare_agent; pause_screen ;;
          8) run_action configure_vnc_port; pause_screen ;;
          7) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    4)
      while true; do
        show_browser_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action install_chromium; pause_screen ;;
          2) run_action install_firefox; pause_screen ;;
          3) run_action configure_kiosk; pause_screen ;;
          4) run_action start_kiosk_now; pause_screen ;;
          5) run_action show_kiosk_config; pause_screen ;;
          6) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    5)
      while true; do
        show_diag_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action show_diagnostics; pause_screen ;;
          2) run_action check_auto_login; pause_screen ;;
          3) run_action check_power_saving_status; pause_screen ;;
          4) run_action fix_network_gui; pause_screen ;;
          5) run_action install_conky_ip_overlay; pause_screen ;;
          6) run_action show_vnc_ports; pause_screen ;;
          7) run_action cleanup_temp_files; pause_screen ;;
          8) run_action disable_auto_updates; pause_screen ;;
          9) run_action check_auto_updates_status; pause_screen ;;
          10) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    6)
      while true; do
        show_theme_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action theme_install_programs; pause_screen ;;
          2) run_action theme_download_images; pause_screen ;;
          3) run_action theme_create_boot_theme; pause_screen ;;
          4) run_action theme_set_wallpaper; pause_screen ;;
          5) run_action theme_run_all; pause_screen ;;
          6) run_action theme_show_status; pause_screen ;;
          7) run_action theme_test_boot_theme; pause_screen ;;
          8) run_action theme_restore_boot_theme; pause_screen ;;
          9) run_action theme_restore_wallpaper; pause_screen ;;
          10) run_action theme_restore_boot_theme; run_action theme_restore_wallpaper; pause_screen ;;
          11) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    7)
      while true; do
        show_clone_menu
        read -rp "Scelta: " C || exit 0
        case "$C" in
          1) run_action prepare_for_clone; pause_screen ;;
          2) run_action post_clone_setup; pause_screen ;;
          3) break ;;
          *) echo "Scelta non valida." ;;
        esac
      done
      ;;
    8)
      echo
      read -rp "Vuoi riavviare il sistema ora? [s/N]: " CONFIRM_REBOOT || exit 0
      if [[ "$CONFIRM_REBOOT" == "s" || "$CONFIRM_REBOOT" == "S" ]]; then
        reboot
      else
        echo "Riavvio annullato."
        pause_screen
      fi
      ;;
    9) exit 0 ;;
    *) echo "Scelta non valida." ;;
  esac
done

}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
