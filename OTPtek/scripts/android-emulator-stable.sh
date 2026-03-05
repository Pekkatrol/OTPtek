#!/usr/bin/env bash
set -euo pipefail

AVD_NAME="${1:-OTPtek}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
ADB_BIN="$ANDROID_SDK_ROOT/platform-tools/adb"
AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
CFG_FILE="$AVD_DIR/config.ini"

if [[ ! -x "$EMULATOR_BIN" ]]; then
  echo "Erreur: émulateur introuvable: $EMULATOR_BIN"
  exit 1
fi

if [[ ! -x "$ADB_BIN" ]]; then
  echo "Erreur: adb introuvable: $ADB_BIN"
  exit 1
fi

if [[ ! -d "$AVD_DIR" || ! -f "$CFG_FILE" ]]; then
  echo "Erreur: AVD introuvable: $AVD_NAME"
  echo "Vérifie avec: $EMULATOR_BIN -list-avds"
  exit 1
fi

ensure_kv() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$CFG_FILE"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$CFG_FILE"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$CFG_FILE"
  fi
}

# Force une configuration stable à chaque exécution.
ensure_kv "hw.gpu.mode" "swiftshader_indirect"
ensure_kv "fastboot.forceColdBoot" "yes"
ensure_kv "snapshot.present" "no"
ensure_kv "PlayStore.enabled" "no"

rm -f "$AVD_DIR/quickbootChoice.ini" "$AVD_DIR/read-snapshot.txt" || true

"$ADB_BIN" start-server >/dev/null

# Si l'AVD est déjà lancé et utilisable, ne pas relancer.
for serial in $("$ADB_BIN" devices | awk 'NR>1 && /emulator-/{print $1}'); do
  if "$ADB_BIN" -s "$serial" shell getprop ro.boot.qemu.avd_name 2>/dev/null | grep -q "^${AVD_NAME}$"; then
    state=$("$ADB_BIN" -s "$serial" get-state 2>/dev/null || true)
    if [[ "$state" == "device" ]]; then
      echo "AVD déjà prêt: $serial ($AVD_NAME)"
      exit 0
    fi
  fi
done

# Démarre l'émulateur en arrière-plan depuis ce script.
nohup "$EMULATOR_BIN" -avd "$AVD_NAME" -no-snapshot -wipe-data -gpu swiftshader_indirect > /tmp/${AVD_NAME}.emulator.log 2>&1 &

# Attend qu'un émulateur passe en état device.
for _ in $(seq 1 120); do
  serial=$("$ADB_BIN" devices | awk 'NR>1 && /emulator-.*device$/{print $1; exit}')
  if [[ -n "${serial:-}" ]]; then
    boot=$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [[ "$boot" == "1" ]]; then
      echo "AVD prêt: $serial"
      exit 0
    fi
  fi
  sleep 2
done

echo "Erreur: timeout de démarrage de l'AVD ($AVD_NAME)"
echo "Logs: /tmp/${AVD_NAME}.emulator.log"
exit 1
