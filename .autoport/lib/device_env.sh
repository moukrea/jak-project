# Canonical device layout (Grecharged-buildsys-firstboot). Source this; NEVER
# redeclare these as `local` in functions (local S= shadows the adb serial).
S=${S:-eae4df44}
PKG=${PKG:-org.opengoal.gk.jak1}
DEVICE_GAME_BASE=/storage/emulated/0/OpenGOAL
DEVICE_GAME_ROOT="$DEVICE_GAME_BASE/jak1"
DEVICE_ASSETS="$DEVICE_GAME_ROOT/assets"
DEVICE_SAVES="$DEVICE_GAME_ROOT/saves"
DEVICE_CUSTOM_ASSETS="$DEVICE_GAME_ROOT/custom_assets"
DEVICE_SETTINGS_INI="$DEVICE_GAME_ROOT/settings.ini"
