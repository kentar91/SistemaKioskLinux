# DS Monitor — setup Ubuntu

Script interattivo per Ubuntu con APT e systemd. La versione rivista è
`ds-monitor-setup-ubuntu.sh`, in UTF-8 con terminatori Unix LF.
Il file originale in Download non è stato modificato.

```bash
sudo bash ds-monitor-setup-ubuntu.sh
```

## Blocca aggiornamenti

Menu **1 — Sistema → 8 — Blocca aggiornamenti software e firmware**,
disponibile anche in **5 — Diagnostica → 8**. Blocca gli aggiornamenti automatici;
quelli richiesti dal tecnico restano disponibili.
Il punto **9** controlla APT, hold Snap e maschere systemd e restituisce un errore
se il blocco non risulta completo o un servizio è ancora attivo.

La vecchia funzione è stata sostituita. La nuova implementazione comprende:

- Configurazione APT con precedenza elevata e disattivazione delle proposte di
  aggiornamento della distribuzione.
- Maschere persistenti per APT, unattended-upgrades, PackageKit, ricerca automatica fwupd,
  systemd-sysupdate e timer Flatpak conosciuti, comprese unità non installate.
- `snap refresh --hold=forever`, senza disattivare snapd o le applicazioni Snap.
  Il comando deve essere supportato da snapd; un errore viene segnalato.
- Impostazioni e blocchi dconf per GNOME Software/update-notifier e disattivazione
  degli autostart conosciuti. I file di sistema restano leggibili dagli utenti.
- Backup per ogni esecuzione in `/var/backups/kiosk-updates.*`, con file originali,
  elenco dei file creati, stato iniziale delle unità e informazioni Snap.

Eseguire durante la manutenzione. Vengono fermati soltanto i timer: i servizi che
potrebbero installare pacchetti o firmware non vengono terminati. Attendere la
fine delle installazioni, riavviare e ripetere la verifica. Il blocco globale dei
servizi utente richiede una nuova sessione.

Gli override di autostart presenti nelle home vengono segnalati e, se non già
disabilitati, rendono il risultato incompleto: non vengono riscritti come root.
Unità locali che impediscono `systemctl mask` producono un errore esplicito.
Il controllo del menu 9 non certifica le impostazioni effettive di ogni sessione
desktop: profili dconf personalizzati, unità utente e cron personalizzati,
Discover, updater interni alle app e strumenti di gestione remota richiedono
una verifica dedicata. Non è un blocco assoluto delle modifiche amministrative.

Gli aggiornamenti manuali APT rimangono disponibili:

```bash
sudo apt update && sudo apt upgrade
```

Il blocco comprende anche gli aggiornamenti automatici di sicurezza.
Per Snap il comportamento di hold e refresh manuale è descritto nella
[documentazione ufficiale](https://snapcraft.io/docs/how-to-guides/manage-snaps/manage-updates/).

## Scelta manuale di software e firmware

Il programma mantiene il menu e le funzioni esistenti. Nel menu **1 — Sistema**
sono presenti le voci **8 — Blocca aggiornamenti software e firmware**,
**9 — Firmware** e **10 — Aggiorna software / scarica pacchetti**.
Nessuna di queste viene eseguita automaticamente all'avvio
o dal blocco degli aggiornamenti.

La voce 10 permette ricerca APT, upgrade con conferma, solo download APT,
aggiornamento di un pacchetto specifico, ricerca Snap, aggiornamento di una app
Snap specifica e aggiornamento interattivo dei Flatpak di sistema. L'hold Snap
non viene rimosso. Per i Flatpak installati nel profilo utente usare `flatpak
--user update` dalla sessione dell'utente interessato.
La voce originale **2 — Aggiornamento completo sistema** rimane disponibile:
APT mostra il piano e richiede conferma, senza pulizia automatica dei pacchetti.
Anche l'installazione dei driver richiede conferma dopo la visualizzazione.

La voce 9 aggiunge il supporto firmware prima assente:

- Installazione esplicita del pacchetto `fwupd`, se necessario.
- Visualizzazione dispositivi e versioni firmware.
- Ricerca aggiornamenti: scarica il catalogo, senza installare firmware.
- Download e installazione su un dispositivo scelto o su tutti, con conferma.
- Installazione di un file `.cab` locale dopo la visualizzazione dei dettagli.
- Consultazione dello storico.

Il download del firmware online avviene insieme all'installazione confermata;
la voce di ricerca scarica soltanto i metadati. Non vengono usate opzioni di
conferma automatica o forzatura. fwupd gestisce compatibilità e richieste di
riavvio. Sono supportati soltanto hardware e firmware resi disponibili tramite
fwupd/LVFS o archivi compatibili del produttore. Il funzionamento segue il
[manuale ufficiale di fwupdmgr](https://github.com/fwupd/fwupd/blob/main/src/fwupdmgr.md).

Il blocco automatico ora lascia disponibili `fwupd.service` e
`fwupd-offline-update.service`: quest'ultimo può essere necessario per completare
un aggiornamento scelto al riavvio. Se erano stati mascherati dalla versione
precedente, una funzione firmware manuale li smaschera senza riattivare i timer
di ricerca. Il daemon disponibile non costituisce un blocco contro altri client
o amministratori che richiedano esplicitamente aggiornamenti.

### Ripristino del blocco

Non è previsto un ripristino automatico. Usare il backup dell'esecuzione da
annullare: ripristinare i file originali nei rispettivi percorsi e rimuovere solo
i file elencati in `created-files.txt` che appartengono a quell'esecuzione,
dopo aver controllato che non siano stati successivamente modificati.
Eseguire `sudo systemctl daemon-reload` e, se installato, `sudo dconf update`.
Riavviare e confrontare le unità con lo stato salvato. Non smascherare
indiscriminatamente unità che erano già bloccate prima del setup.
Per togliere l'hold Snap usare `sudo snap refresh --unhold` solo se si vuole
rimuovere anche un eventuale hold preesistente; consultare i file Snap del backup.
La vecchia configurazione `20auto-upgrades`, se già presente sul PC, è conservata:
la nuova configurazione la supera senza distruggere impostazioni precedenti.

## Altre correzioni

- Azioni di menu eseguite con arresto sugli errori, conservando il menu principale;
  fine dell'input gestita senza cicli infiniti.
- Validazione IPv4, hostname e porta VNC; rete applicata con `netplan try` e
  ripristino del file gestito in caso di errore. Altri file Netplan possono
  ancora influire sulla configurazione finale: controllarli dalla console.
- URL kiosk HTTP/HTTPS con quoting Bash, modalità Chromium `--kiosk` e processi
  browser limitati all'utente monitor.
- Porta VNC persistente in systemd, senza avvio parallelo manuale; voce dedicata
  nel menu Accesso remoto. Sessione X11 necessaria.
- Password degli utenti esistenti conservate; rimangono i valori iniziali
  `monitor` del setup originale per nuovi utenti e nuove configurazioni VNC.
- Backup dello sfondo letto come dati, mai eseguito come script root.
- Download con timeout e controllo errori; tema Plymouth salvato prima della
  modifica; pulizia temporanei affidata a systemd-tmpfiles.
- Nuovo machine-id persistente dopo clonazione, numero macchina validato prima
  di rigenerare identità e chiavi SSH; riavvio necessario.
- Chiave Livecare limitata al repository tramite `signed-by`; installazione
  fermata sulle versioni diverse da Ubuntu 22.04, per cui il repository originale
  non è stato verificato.

## Verifiche

```bash
bash -n ds-monitor-setup-ubuntu.sh
bash tests/test-setup.sh
```

Verificati con Bash 5.2: sintassi, validazione input, quoting URL, controlli del
blocco con systemd/APT/Snap simulati e arresto dopo errore APT.
Non sono stati eseguiti installazioni, modifiche a Ubuntu o test su un kiosk reale.
Restano da collaudare su Ubuntu il ciclo blocco/riavvio, la sessione grafica,
Netplan, VNC e il tema di avvio.
