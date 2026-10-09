#!/usr/bin/env bash
# Test senza root: nessuna funzione di installazione viene eseguita sul sistema.
set -Eeuo pipefail
set +o posix
cd "$(dirname "$0")/.."
source ./ds-monitor-setup-ubuntu.sh

if [[ ${1:-} == --apt-failure ]]; then
  apt() { echo "APT simulato fallito" >&2; return 42; }
  reboot() { echo 'ERRORE: reboot non doveva essere chiamato'; return 99; }
  update_full_system
  echo 'ERRORE: esecuzione proseguita dopo errore APT'
  exit 99
fi

expect_ok() { "$@" || { echo "FAIL: $*"; exit 1; }; }
expect_fail() { if "$@"; then echo "FAIL: accettato $*"; exit 1; fi; }
expect_ok valid_ipv4 192.168.1.2
expect_ok valid_ipv4 0.0.0.0
expect_ok valid_ipv4 255.255.255.255
expect_fail valid_ipv4 256.0.0.1
expect_fail valid_ipv4 '1.2.3.4;id'
expect_fail valid_ipv4 1.2.3
expect_ok valid_hostname ds-monitor-01
expect_fail valid_hostname '-bad'
expect_fail valid_hostname 'bad/name'
[[ $(mask_to_cidr 255.255.255.0) == 24 ]]
expect_fail mask_to_cidr 255.0.255.0

# Verifica che l'escaping dell'URL conservi i dati, senza eseguire metacaratteri.
url='https://example.test/";$(touch SHOULD_NOT_EXIST);#'
printf -v escaped '%q' "$url"
decoded=$("$BASH" -c "printf '%s' $escaped")
[[ "$decoded" == "$url" && ! -e SHOULD_NOT_EXIST ]]

# Stato reale simulato, compresi override e servizi ancora attivi.
systemctl() {
  case "$*" in
    *LoadState*) printf '%s\n' "${MOCK_LOAD:-masked}" ;;
    *ActiveState*) printf '%s\n' "${MOCK_ACTIVE:-inactive}" ;;
    *) return 88 ;;
  esac
}
apt-config() { printf "RESULT='%s'\n" "${MOCK_APT:-0}"; }
readlink() { printf '/dev/null\n'; }
snap() { printf 'hold: %s\n' "${MOCK_HOLD:-forever}"; }
expect_ok check_auto_updates_status >/dev/null
MOCK_LOAD=loaded expect_fail check_auto_updates_status >/dev/null 2>&1
MOCK_ACTIVE=active expect_fail check_auto_updates_status >/dev/null 2>&1
MOCK_APT=1 expect_fail check_auto_updates_status >/dev/null 2>&1
MOCK_HOLD=tomorrow expect_fail check_auto_updates_status >/dev/null 2>&1

status=0
output=$("$BASH" tests/test-setup.sh --apt-failure 2>&1) || status=$?
[[ "$status" == 42 && "$output" != *'ERRORE:'* ]]

# Nessun accesso hardware: controllo selezione, conferma e comandi firmware.
(
  fwupdmgr() { printf 'FWCMD:%s\n' "$*"; return "${FW_STATUS:-0}"; }
  systemctl() {
    case "$*" in
      *LoadState*) echo masked ;;
      *) printf 'SYSCMD:%s\n' "$*" ;;
    esac
  }
  output=$(manual_firmware_updates <<< $'3')
  [[ "$output" == *'FWCMD:refresh'* && "$output" == *'FWCMD:get-updates'* ]]
  [[ "$output" != *'FWCMD:update'* && "$output" != *'unmask fwupd-refresh'* ]]
  [[ "$output" == *'unmask fwupd.service'* && "$output" == *'unmask fwupd-offline-update.service'* ]]
  output=$(manual_firmware_updates <<< $'4\nTUTTI\nn')
  [[ "$output" != *'FWCMD:update'* ]]
  output=$(manual_firmware_updates <<< $'4\naabbccdd\ns')
  [[ "$output" == *'FWCMD:update aabbccdd'* && "$output" != *'--assume-yes'* ]]
  FW_STATUS=2 expect_ok firmware_command get-updates >/dev/null
  FW_STATUS=1 expect_fail firmware_command update >/dev/null
  apt() { printf 'APTCMD:%s\n' "$*"; }
  apt-get() { printf 'APTGETCMD:%s\n' "$*"; }
  output=$(manual_software_updates <<< '3')
  [[ "$output" == *'APTGETCMD:--download-only upgrade'* && "$output" != *'APTCMD:upgrade'* ]]
  snap() { printf 'SNAPCMD:%s\n' "$*"; }
  output=$(manual_software_updates <<< $'6\nfirefox\ns')
  [[ "$output" == *'SNAPCMD:refresh firefox'* && "$output" != *'--unhold'* ]]
)
echo 'PASS: validazione input, quoting URL, verifica blocco e arresto su errore APT.'
echo 'PASS: ricerca firmware senza installazione, annullamento, selezione dispositivo, errori fwupd, solo download APT e Snap manuale.'
