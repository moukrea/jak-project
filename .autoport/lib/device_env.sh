# Canonical device layout (Grecharged-buildsys-firstboot). Source this; NEVER
# redeclare these as `local` in functions (local S= shadows the adb serial).
# Owner 2026-09-06 : n'importe quel appareil branche sert de preuve, le plus rapide gagne.
S=${S:-${ANDROID_SERIAL:-$(bash "$(dirname "${BASH_SOURCE[0]}")/pick_device.sh" 2>/dev/null)}}
PKG=${PKG:-org.opengoal.gk.jak1}
DEVICE_GAME_BASE=/storage/emulated/0/OpenGOAL
DEVICE_GAME_ROOT="$DEVICE_GAME_BASE/jak1"
DEVICE_ASSETS="$DEVICE_GAME_ROOT/assets"
DEVICE_SAVES="$DEVICE_GAME_ROOT/saves"
DEVICE_CUSTOM_ASSETS="$DEVICE_GAME_ROOT/custom_assets"
DEVICE_SETTINGS_INI="$DEVICE_GAME_ROOT/settings.ini"
