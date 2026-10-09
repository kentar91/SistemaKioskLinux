# DS Monitor — guida completa per i tecnici

`ds-monitor-setup-ubuntu.sh` configura un PC Ubuntu come postazione kiosk. Ogni operazione si sceglie dal menu: avviare il programma non avvia automaticamente installazioni o aggiornamenti.

**Flusso previsto:** installare il PC → aggiornare manualmente software, driver e firmware → configurare il kiosk → bloccare gli aggiornamenti automatici → aggiornare nuovamente soltanto quando lo decide il tecnico.

## Indice

- [Download e avvio](#download-e-avvio)
- [Prima installazione](#prima-installazione)
- [Menu principale](#menu-principale)
- [1 — Sistema](#1--sistema)
- [2 — Rete](#2--rete)
- [3 — Accesso remoto](#3--accesso-remoto)
- [4 — Browser e kiosk](#4--browser-e-kiosk)
- [5 — Diagnostica](#5--diagnostica)
- [6 — Grafica](#6--grafica)
- [7 — Clonazione](#7--clonazione)
- [8 — Riavvia sistema e 9 — Esci](#8--riavvia-sistema-e-9--esci)
- [Manutenzione dopo il blocco](#manutenzione-dopo-il-blocco)
- [Backup e ripristino](#backup-e-ripristino)
- [Problemi frequenti e limiti](#problemi-frequenti-e-limiti)
- [File gestiti](#file-gestiti)
- [Verifiche](#verifiche)

## Download e avvio

Repository: [kentar91/SistemaKioskLinux](https://github.com/kentar91/SistemaKioskLinux).

Su Ubuntu:

```bash
wget "https://raw.githubusercontent.com/kentar91/SistemaKioskLinux/main/ds-monitor-setup-ubuntu.sh" -O ds-monitor-setup-ubuntu.sh &&
bash -n ./ds-monitor-setup-ubuntu.sh &&
sudo bash ./ds-monitor-setup-ubuntu.sh
```

Il primo comando scarica il file, il secondo controlla la sintassi senza eseguirlo, il terzo apre il menu. I comandi successivi partono solo se il precedente riesce. Con `sudo bash` non serve `chmod +x`. Un nuovo download sostituisce il file omonimo nella cartella corrente, comprese eventuali personalizzazioni.

Requisiti: Ubuntu con APT, systemd, Bash e privilegi amministrativi. Internet serve per pacchetti, immagini e firmware. Le funzioni grafiche presuppongono GNOME/GDM e una sessione X11; quelle di rete usano Netplan con NetworkManager. Ubuntu Server senza desktop non dispone automaticamente di tutte queste componenti.

| Impostazione iniziale | Valore | Comportamento |
| --- | --- | --- |
| Utente kiosk | `monitor` | Usato per login, browser, VNC e desktop. |
| Password nuovo utente | `monitor` | Impostata solo alla creazione; una password esistente viene conservata. |
| Password nuovo VNC | `monitor` | Usata se manca il file password VNC. |
| Hostname predefinito | `ds-monitor` | Usato dalla funzione di reset hostname. |

L'utente monitor viene aggiunto al gruppo `sudo`. Personalizzare le credenziali iniziali prima della messa in servizio; non c'è un menu dedicato alla rotazione delle password.

## Prima installazione

La notazione **Sistema → 4** significa: scegliere **1** nel menu principale, poi **4** nel sottomenu.

1. **Sistema → 4:** creare l'utente monitor.
2. **Sistema → 1**, poi **3:** aggiornare l'indice e installare gli strumenti base.
3. **Rete:** impostare hostname e, se necessario, IP statico; altrimenti mantenere DHCP.
4. **Sistema → 2:** aggiornare Ubuntu, leggendo il piano APT prima di confermare.
5. **Sistema → 5:** controllare i driver e confermare l'installazione se necessaria.
6. **Sistema → 9:** installare fwupd se manca, cercare firmware e scegliere quali installare.
7. Completare i riavvii richiesti e riaprire lo script.
8. **Browser e kiosk → 1 o 2**, poi **3:** installare il browser e impostare l'URL.
9. **Sistema → 6:** configurare ALWAYS ON, login automatico e X11.
10. **Accesso remoto:** installare gli strumenti necessari; leggere il limite Livecare sotto.
11. Facoltativamente configurare **Grafica** e **Diagnostica → 5** per l'overlay IP.
12. Terminate tutte le installazioni, **Sistema → 8:** bloccare gli aggiornamenti automatici software e firmware.
13. Riavviare, controllare il kiosk ed eseguire **Diagnostica → 9** per verificare il blocco.

Il blocco richiede una scelta esplicita. Le funzioni interne `full_setup` e `show_setup_menu` non sono collegate al menu principale: non c'è una procedura interattiva «Setup completo macchina» nella versione attuale.

## Menu principale

| Numero | Sezione | Scopo |
| --- | --- | --- |
| 1 | Sistema | Utente, pacchetti, driver, firmware, ALWAYS ON e blocco automatici. |
| 2 | Rete | IP, DHCP, hostname e stato rete. |
| 3 | Accesso remoto | SSH, VNC e Livecare. |
| 4 | Browser e kiosk | Browser e pagina del kiosk. |
| 5 | Diagnostica | Stato del PC, manutenzione e verifica blocco. |
| 6 | Grafica | Logo di avvio Plymouth e sfondo. |
| 7 | Clonazione | Preparazione sorgente e identità dei cloni. |
| 8 | Riavvia sistema | Riavvio con conferma. |
| 9 | Esci | Chiusura del programma. |

Dopo un'azione, Invio riporta al menu. Gli errori interrompono normalmente l'azione e vengono segnalati: non comportano un rollback completo delle modifiche precedenti. Alcuni passaggi opzionali ignorano gli errori; controllare anche il risultato sul PC.

## 1 — Sistema

| Voce | Funzionamento e uso |
| --- | --- |
| 1 — Aggiorna elenco pacchetti | Esegue `apt update`, senza installare nuove versioni. |
| 2 — Aggiornamento completo sistema | Esegue `apt update` e `apt full-upgrade`. Leggere e confermare il piano: APT può installare o rimuovere pacchetti per risolvere dipendenze. Alla fine chiede se riavviare. Non aggiorna tutti i firmware o le app Snap/Flatpak. |
| 3 — Installa pacchetti base | Installa curl, wget, GnuPG, certificati, strumenti repository, net-tools, unzip, openssl, xdotool e utility X11. La selezione avvia APT con conferma automatica. |
| 4 — Crea utente monitor | Crea l'utente se assente, prepara le cartelle e aggiunge il gruppo sudo. Eseguire prima di kiosk, ALWAYS ON e VNC. |
| 5 — Aggiornamento driver di sistema | Aggiorna l'indice, installa ubuntu-drivers-common se manca, elenca i driver e chiede conferma per installare quelli consigliati. Riavvio consigliato. Driver e firmware sono operazioni distinte. |
| 6 — Modalità ALWAYS ON | Configura auto-login GDM, disabilita Wayland, blocco schermo/inattività e sospensione; crea l'autostart delle impostazioni desktop. Richiede monitor e desktop compatibile. Riavviare e verificare. Non riavvia immediatamente logind. |
| 7 — Torna indietro | Ritorna al menu principale. |
| 8 — Blocca aggiornamenti software e firmware | Blocca gli automatismi conosciuti, crea backup e verifica il risultato. Dettaglio sotto. |
| 9 — Firmware | Apre le operazioni manuali firmware. |
| 10 — Aggiorna software / scarica pacchetti | Apre le operazioni software manuali, disponibili anche dopo il blocco. |

### Sistema → 8: blocco degli automatici

La stessa funzione è disponibile in **Diagnostica → 8**. Blocca gli aggiornamenti automatici, lasciando disponibili quelli richiesti dal tecnico.

1. Crea un backup in `/var/backups/kiosk-updates.*`.
2. Disabilita le attività periodiche APT e il riavvio automatico unattended-upgrades.
3. Imposta `Prompt=never` per le proposte di nuova distribuzione.
4. Maschera timer/servizi APT, unattended-upgrades, PackageKit, ricerca automatica fwupd, systemd-sysupdate e aggiornatori Flatpak conosciuti.
5. Imposta `snap refresh --hold=forever`, conservando snapd e le app Snap.
6. Applica impostazioni/lock dconf GNOME e disabilita gli autostart di aggiornamento conosciuti a livello di sistema.
7. Controlla il risultato e segnala eventuali blocchi incompleti.

Ferma soltanto i timer: non termina servizi che potrebbero installare software o firmware. Attendere la fine delle installazioni, riavviare e ripetere **Diagnostica → 9**. Per le unità utente è necessaria una nuova sessione.

`fwupd.service` e `fwupd-offline-update.service` restano disponibili per gli aggiornamenti manuali e il loro completamento al riavvio. Le funzioni firmware manuali rimuovono eventuali vecchie maschere su queste due unità, senza riabilitare i timer di ricerca.

Il blocco comprende anche gli aggiornamenti automatici di sicurezza. Non copre ogni updater interno alle app, cron personalizzato, agente remoto, profilo dconf alternativo o unità utente personalizzata. Gli override autostart nelle home vengono segnalati, non riscritti come root. Snap deve supportare l'hold permanente; un errore non viene presentato come successo.

### Sistema → 9: firmware

| Voce | Funzionamento |
| --- | --- |
| 1 — Installa il supporto firmware fwupd | Aggiorna l'indice APT e propone l'installazione di fwupd. Non installa firmware. |
| 2 — Mostra dispositivi e versioni firmware | Mostra i dispositivi rilevati con `fwupdmgr get-devices`. |
| 3 — Cerca firmware disponibili | Scarica/aggiorna il catalogo e mostra gli aggiornamenti. Non installa firmware. |
| 4 — Scarica e installa firmware | Aggiorna il catalogo, mostra le disponibilità, chiede un ID dispositivo oppure `TUTTI`. Invio annulla. Richiede conferma prima dell'aggiornamento. |
| 5 — Installa firmware locale .cab | Chiede il percorso assoluto di un file esistente, mostra i dettagli e chiede conferma per installarlo. |
| 6 — Mostra storico | Mostra lo storico fwupd. |
| 0 — Annulla | Ritorna senza operazioni. |

Se fwupd manca, usare prima la voce 1. Le altre voci avviano il suo servizio per l'operazione manuale. Il download del firmware online avviene insieme all'installazione confermata: non c'è una voce «solo download firmware». La ricerca scarica soltanto metadati.

Disponibilità e compatibilità dipendono da fwupd/LVFS e dal produttore: non tutti i BIOS o dispositivi hanno firmware disponibili. Non interrompere l'alimentazione durante il flash. fwupd mantiene le proprie conferme e richieste di riavvio; lo script non forza l'installazione. «Nessuna operazione disponibile» non è trattato come errore generico.

### Sistema → 10: software a richiesta

| Voce | Funzionamento |
| --- | --- |
| 1 — Cerca aggiornamenti APT | Aggiorna l'indice e mostra i pacchetti aggiornabili senza installare. |
| 2 — Aggiorna pacchetti APT | Esegue `apt upgrade` con conferme APT. |
| 3 — Scarica soltanto aggiornamenti APT | Esegue `apt-get --download-only upgrade`, senza installare. Per installare successivamente usare la voce 2; non è una procedura offline garantita. |
| 4 — Aggiorna un pacchetto APT | Chiede il nome e usa `apt install --only-upgrade`; APT può includere dipendenze. |
| 5 — Cerca aggiornamenti Snap | Mostra `snap refresh --list`, senza installare. Snap deve essere presente. |
| 6 — Aggiorna una app Snap | Mostra le app, chiede nome e conferma. Aggiorna l'app senza rimuovere l'hold. |
| 7 — Aggiorna app Flatpak di sistema | Esegue l'aggiornamento interattivo dei Flatpak di sistema, se Flatpak è installato. |
| 0 — Annulla | Ritorna senza operazioni. |

Per i Flatpak del singolo utente usare `flatpak --user update` dalla sua sessione, senza sudo. Alla fine di ogni scelta si torna al menu Sistema: riaprire la voce 10 per un'altra operazione.

## 2 — Rete

| Voce | Funzionamento |
| --- | --- |
| 1 — Imposta IP statico | Rileva la scheda e chiede IPv4, maschera, gateway, DNS1 e DNS2. I DNS vuoti assumono 1.1.1.1 e 8.8.8.8. Scrive `/etc/netplan/99-ds-monitor.yaml`. |
| 2 — Imposta DHCP | Configura DHCP IPv4 sulla scheda rilevata nello stesso file. |
| 3 — Cambia hostname | Chiede un nome valido e aggiorna hostname e riga 127.0.1.1 in `/etc/hosts`. |
| 4 — Reset hostname | Imposta `ds-monitor` e aggiorna `/etc/hosts`. |
| 5 — Mostra configurazione rete | Mostra hostname, IP, route e file Netplan. |
| 6 — Torna indietro | Ritorna al menu principale. |

IP statico e DHCP usano `netplan try` con 120 secondi per confermare. In caso di errore viene ripristinato anche il file gestito; verificare comunque la connettività dalla console. Altri file Netplan possono influire sul risultato. Il renderer impostato è NetworkManager.

Se non viene rilevata Ethernet, viene tentata l'interfaccia della route principale: controllare quella mostrata prima di procedere. Non c'è una procedura dedicata per SSID/password Wi-Fi o IPv6.

## 3 — Accesso remoto

| Voce | Funzionamento |
| --- | --- |
| 1 — Installa SSH | Installa openssh-server, abilita e riavvia il servizio ssh. |
| 2 — Installa VNC | Installa x11vnc, disabilita Wayland e configura il servizio per monitor sulla porta 5900. Conserva una password VNC già presente. |
| 3 — Installa Livecare Agent | Usa il repository del produttore xUbuntu_22.04 e importa la chiave in trusted.gpg.d. Nella versione attuale non verifica la versione Ubuntu. |
| 4 — Verifica servizi remoti | Mostra stato SSH/VNC e presenza del pacchetto Livecare. |
| 5 — Disinstalla VNC | Ferma/disabilita il servizio, rimuove configurazione/password gestite, regola UFW della porta salvata e pacchetto; esegue anche autoremove. |
| 6 — Disinstalla Livecare Agent | **Non usare per disinstallare: la funzione attuale contiene per errore una procedura di installazione.** Vedere i limiti sotto. |
| 7 — Torna indietro | Ritorna al menu principale. |
| 8 — Configura porta VNC persistente | Chiede una porta 1024–65535, riscrive e riavvia il servizio. VNC deve essere già installato. |

VNC richiede una sessione X11 attiva su `:0`. Riavviare dopo aver disabilitato Wayland. Se UFW è presente, aggiunge la regola della porta scelta e rimuove quella precedente conosciuta. Non attiva UFW e non configura router/NAT. Reinstallare VNC con la voce 2 reimposta la porta 5900. Non viene configurato un tunnel o una cifratura di trasporto VNC.

## 4 — Browser e kiosk

| Voce | Funzionamento |
| --- | --- |
| 1 — Installa Chromium | Prova APT chromium-browser, poi Snap se il comando fallisce. |
| 2 — Installa Firefox | Prova APT firefox, poi Snap se il comando fallisce. |
| 3 — Configura kiosk | Chiede URL HTTP/HTTPS senza spazi e browser chromium/firefox. Richiede monitor e browser installato. |
| 4 — Avvia manualmente il kiosk | Avvia lo script kiosk come monitor sulla sessione grafica :0. |
| 5 — Mostra configurazione kiosk | Visualizza URL, browser, modalità e stato auto-restart salvati. |
| 6 — Torna indietro | Ritorna al menu principale. |

La configurazione crea script e autostart. Dopo il login attende circa 20 secondi, chiude i processi del browser interessato dell'utente monitor e apre la pagina in modalità kiosk. Chromium usa anche incognito e no-first-run. Il login automatico viene configurato da **Sistema → 6**.

**Non è previsto il riavvio automatico del browser se si chiude o termina con un errore**: il file di configurazione riporta `AUTO_RESTART=no`.

## 5 — Diagnostica

| Voce | Funzionamento |
| --- | --- |
| 1 — Mostra diagnostica completa | Mostra hostname, IP locale/pubblico, machine-id, servizi, browser, auto-login e kiosk. L'IP pubblico viene richiesto a ifconfig.me. |
| 2 — Controlla auto-login | Verifica i valori GDM per monitor; non dimostra che un login reale sia riuscito. |
| 3 — Check risparmio energia | Mostra autostart, logind/sleep e target di sospensione. Controlla anche un file screenoff che questa versione non crea. |
| 4 — Fix rete GUI | Salva i file Netplan, sostituisce renderer networkd con NetworkManager e propone netplan try. Può modificare anche file diversi da quello DS Monitor. |
| 5 — Installa overlay IP desktop | Installa Conky e autostart con hostname, IP locale/pubblico e ora nell'angolo inferiore destro. |
| 6 — Mostra porte VNC | Mostra stato servizio, porte e regole UFW; il filtro copre soltanto 5900–5905. |
| 7 — Pulizia file temporanei | Esegue autoremove APT senza ulteriore conferma, autoclean, pulizia journal a 7 giorni e systemd-tmpfiles --clean. Può rimuovere pacchetti non più necessari e log archiviati. |
| 8 — Blocca aggiornamenti software e firmware | Stessa funzione di Sistema → 8. |
| 9 — Verifica stato aggiornamenti automatici | Controlla maschere/stati systemd, opzioni periodiche APT, maschere utente globali e hold Snap; segnala controlli non superati. |
| 10 — Torna indietro | Ritorna al menu principale. |

La verifica non certifica ogni profilo desktop o updater personalizzato. Per una porta VNC fuori da 5900–5905 utilizzare anche `sudo ss -tlnp` e `sudo systemctl status x11vnc.service`.

## 6 — Grafica

Le immagini vengono scaricate da `https://www.sistemipos.it/sh`: `SistemiPOS_logo.png` e `SistemiPos_Wallpaper.jpg`. L'utente scelto è monitor, se esiste, altrimenti quello che ha avviato sudo. I file vengono salvati nella sua cartella `Immagini`.

| Voce | Funzionamento |
| --- | --- |
| 1 — Installa programmi necessari | Aggiorna l'indice e installa wget, curl, ImageMagick e Plymouth. |
| 2 — Scarica logo e sfondo | Scarica le immagini con timeout e controllo errori. |
| 3 — Crea e attiva tema avvio | Ridimensiona il logo a 500 pixel di larghezza sovrascrivendo l'immagine scaricata, salva un tema esistente, crea/seleziona il tema sistemi-pos e aggiorna initramfs. |
| 4 — Imposta wallpaper | Salva URI/opzioni precedenti se manca il backup e imposta sfondo GNOME, zoom e colori neri. Richiede immagini e sessione compatibile. |
| 5 — Esegui tutto | Dopo conferma esegue strumenti, download, tema di avvio e wallpaper. Riguarda soltanto la grafica. |
| 6 — Mostra stato | Mostra utente, percorsi, immagini, backup e tema corrente. |
| 7 — Test anteprima tema avvio | Avvia un'anteprima Plymouth di circa 5 secondi; può cambiare temporaneamente lo schermo. |
| 8 — Ripristina tema avvio originale | Apre la scelta dei temi installati e aggiorna initramfs. Il tecnico sceglie il tema; non viene ripristinata automaticamente una scelta precedente salvata. |
| 9 — Ripristina wallpaper precedente/predefinito | Ripristina URI/opzioni dal backup o valori predefiniti se assente. Non ripristina tutti i colori modificati. |
| 10 — Ripristina tema avvio + wallpaper | Esegue entrambe le operazioni precedenti. |
| 11 — Torna indietro | Ritorna al menu principale. |

Riavviare per verificare il logo nell'avvio reale. Il backup wallpaper viene creato una sola volta, non aggiornato a ogni cambio sfondo.

## 7 — Clonazione

| Voce | Funzionamento |
| --- | --- |
| 1 — Prepara macchina per clonazione | Reimposta hostname ds-monitor e DHCP. Non crea un'immagine disco e non rigenera gli identificativi. |
| 2 — Setup post-clone | Chiede un numero di 1–4 cifre, rigenera machine-id e chiavi host SSH, imposta ds-monitor-NN e aggiorna /etc/hosts. |
| 3 — Torna indietro | Ritorna al menu principale. |

Eseguire la voce 1 sulla sorgente, clonare il disco con uno strumento esterno, poi eseguire la voce 2 su ogni clone con un numero distinto (01 → ds-monitor-01). Riavviare per rendere coerente l'identità in uso.

Le nuove chiavi SSH possono produrre un avviso sui client: verificare l'identità prima di aggiornare le chiavi conosciute. La procedura non ripulisce credenziali, cronologia browser, certificati applicativi o identità degli agenti remoti presenti nell'immagine.

## 8 — Riavvia sistema e 9 — Esci

**8** riavvia solo dopo conferma con s/S. **9** chiude lo script. Le modifiche già applicate restano persistenti: uscire non è un rollback.

## Manutenzione dopo il blocco

1. Aprire lo script durante la manutenzione.
2. Usare **Sistema → 10** per software o **Sistema → 9** per firmware.
3. Cercare gli aggiornamenti, scegliere e confermare quelli desiderati.
4. Completare i riavvii richiesti e verificare il kiosk.
5. Eseguire **Diagnostica → 9** per controllare il blocco.

Non serve togliere il blocco per queste operazioni. Snap non esegue --unhold; firmware non riabilita i timer. Un nuovo software potrebbe aggiungere un updater non conosciuto: controllarlo dopo l'installazione.

## Backup e ripristino

| Percorso | Contenuto |
| --- | --- |
| `/var/backups/ds-monitor-file.*` | Backup puntuali delle funzioni che chiamano backup_file; non è un backup completo del PC. |
| `/var/backups/ds-monitor-netplan.*` | Copia del file Netplan gestito prima della modifica, se esisteva. |
| `/var/backups/kiosk-updates.*` | Configurazioni originali, elenco file nuovi created-files.txt, stato unità sistema/utente e informazioni Snap. |
| `~/.config/sistemi-pos/wallpaper_backup.conf` | URI e opzioni dello sfondo dell'utente scelto. |

Non esiste una funzione generale «annulla tutto» o una voce per riattivare tutti gli automatismi. Per annullare un'esecuzione del blocco, confrontare il suo backup con i file attuali, ripristinare gli originali e rimuovere solo i file nuovi elencati che non siano stati successivamente modificati. Eseguire `sudo systemctl daemon-reload`, `sudo dconf update` se disponibile e riavviare.

Confrontare le unità con gli elenchi salvati: non smascherare quelle già bloccate prima del setup. Il vecchio file APT 20auto-upgrades viene conservato, se presente, e può contenere un blocco precedente. `sudo snap refresh --unhold` rimuove l'hold: usarlo soltanto se si intende riattivare quell'automatismo e dopo aver verificato se era preesistente. Non serve per aggiornare manualmente.

## Problemi frequenti e limiti

| Sintomo | Controllo |
| --- | --- |
| Download GitHub fallito | Usare il link Raw, repository SistemaKioskLinux, branch main; verificare rete e visibilità repository. |
| Richiesta root | Avviare con sudo bash. |
| Utente monitor assente | Eseguire Sistema → 4. |
| Kiosk non parte | Verificare browser, URL, X11, auto-login, ritardo iniziale e Browser e kiosk → 5. |
| VNC non disponibile | Controllare servizio, sessione X11, porta, firewall e riavvio dopo Wayland OFF. |
| Blocco incompleto | Leggere i controlli falliti, attendere le installazioni attive, riavviare e verificare di nuovo. Controllare override utente e unità locali. |
| Nessun firmware disponibile | Controllare catalogo e dispositivi; hardware non supportato o già aggiornato sono possibilità. |
| Rete persa | Usare la console, attendere il timeout Netplan e controllare tutti i file /etc/netplan/*.yaml. |
| Wallpaper non cambia | Controllare GNOME, sessione dell'utente, immagini e messaggi gsettings. |

**Anomalia Livecare nella versione documentata:** Accesso remoto → 6 è etichettato «Disinstalla», ma uninstall_livecare_agent contiene un'installazione con signed-by e controllo Ubuntu 22.04. Non usarlo per rimuovere l'agente. La voce 3 usa ancora l'installazione originaria senza quel controllo versione. Questo aggiornamento documentale descrive il comportamento effettivo e non modifica lo script.

## File gestiti

| Percorso | Uso |
| --- | --- |
| `/etc/gdm3/custom.conf` | Auto-login e Wayland. |
| `/etc/hosts` | Nome macchina su 127.0.1.1. |
| `/etc/netplan/99-ds-monitor.yaml` | IP gestito dallo script. |
| `/etc/systemd/logind.conf.d/ds-monitor.conf` | Coperchio/inattività. |
| `/etc/systemd/sleep.conf.d/ds-monitor.conf` | Sospensione/ibernazione. |
| `/usr/local/bin/ds-monitor-disable-power.sh` | Impostazioni desktop ALWAYS ON. |
| `/usr/local/bin/ds-monitor-kiosk.sh` | Avvio browser. |
| `/etc/ds-monitor-kiosk.conf` | Riepilogo kiosk. |
| `/usr/local/bin/ds-monitor-conky.sh` | Avvio overlay. |
| `~monitor/.config/autostart/` | Autostart desktop. |
| `~monitor/.config/conky/conky-ip.conf` | Configurazione overlay. |
| `/etc/systemd/system/x11vnc.service` | Servizio VNC. |
| `/etc/x11vnc/passwd` e `/etc/x11vnc/port` | Password e porta VNC. |
| `/etc/apt/apt.conf.d/99zz-disable-auto-updates` | Blocco periodico APT. |
| `/etc/update-manager/release-upgrades` | Proposte nuova distribuzione. |
| `/etc/dconf/profile/user` e `/etc/dconf/db/local.d/` | Impostazioni GNOME e lock. |
| `/etc/xdg/autostart/` | Override notifier di sistema. |
| `/etc/systemd/system/` e `/etc/systemd/user/` | Maschere servizi/timer. |
| `/usr/share/plymouth/themes/sistemi-pos/` | Tema di avvio. |
| `/etc/machine-id` e `/var/lib/dbus/machine-id` | Identità post-clone. |
| `/etc/ssh/ssh_host_*` | Chiavi SSH post-clone. |

## Verifiche

Dopo aver scaricato l'intero repository:

```bash
bash -n ds-monitor-setup-ubuntu.sh
bash tests/test-setup.sh
```

Sintassi e test simulati sono stati verificati con Bash 5.2. I test coprono input, quoting URL, controllo blocco, errori APT, conferme/selezione firmware, download-only APT e Snap manuale. Non eseguono flash e non dimostrano il funzionamento di tutte le voci su hardware reale. Restano da collaudare su Ubuntu rete, VNC, desktop, tema e ciclo blocco/riavvio.

Riferimenti: [gestione aggiornamenti Snap](https://snapcraft.io/docs/how-to-guides/manage-snaps/manage-updates/) e [manuale fwupdmgr](https://github.com/fwupd/fwupd/blob/main/src/fwupdmgr.md).
