#!/bin/bash
# Genera CleanUninstall-<versión>.dmg con fondo, layout de iconos y enlace a /Applications.
# Mismo molde que los DMG de Calculadora+, TRM Fixer y Peek a Boo. Uso: ./build_dmg.sh
#
# ⚠ Correr SIEMPRE este script, nunca un `hdiutil create` pelado: eso pierde el fondo,
# las posiciones de los iconos y el LÉEME.
#
# Sin .zip a propósito: el DMG ya va comprimido (UDZO) y el zip sólo duplica archivos.
set -e

APP="${APP:-/Applications/CleanUninstall.app}"   # APP=… para armarlo desde otra ruta (pruebas)
VOL="CleanUninstall"
BG="$(dirname "$0")/dmg_assets/background.png"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
OUT="${1:-$HOME/Desktop/CleanUninstall-$VERSION.dmg}"
TMP_DMG="/tmp/CleanUninstall-rw.dmg"
MNT="/Volumes/$VOL"
echo "==> Versión: $VERSION"

echo "==> Limpieza previa"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
rm -f "$TMP_DMG" "$OUT"

# 20m: la app pesa unos 3 MB (va dos veces: la visible y la copia oculta).
echo "==> Creando DMG temporal de lectura/escritura"
hdiutil create -volname "$VOL" -srcfolder "$APP" -fs APFS -format UDRW -size 20m "$TMP_DMG"

echo "==> Montando"
hdiutil attach "$TMP_DMG" -mountpoint "$MNT"

# Transición del nombre: la app se llamaba Triturador hasta la 1.1.0, y el actualizador
# de esa versión busca «Triturador.app» dentro del DMG. Va una copia OCULTA con ese
# nombre; al abrirse desde /Applications/Triturador.app la app se renombra sola.
echo "==> Copia oculta para quien todavía tiene Triturador"
ditto "$APP" "$MNT/Triturador.app"
chflags hidden "$MNT/Triturador.app"   # ⚠ solo en APFS: en HFS+ «oculta» = FinderInfo y rompe la firma

echo "==> Enlace a /Applications, fondo y LÉEME"
ln -s /Applications "$MNT/Applications"
mkdir -p "$MNT/.background"
cp "$BG" "$MNT/.background/background.png"
cat > "$MNT/LÉEME.txt" <<'TXT'
CleanUninstall — Hecho por Snapsis

Arrastra la app sobre "Applications".

PRIMERA VEZ QUE LA ABRAS
  1. Doble clic. macOS dirá que no se puede abrir. Cierra el aviso.
  2. Ve a  Ajustes del Sistema > Privacidad y Seguridad
     y baja hasta el mensaje sobre "CleanUninstall".
  3. Pulsa "Abrir de todos modos" y confirma.
  A partir de ahí abre con doble clic como cualquier app.

  Las versiones siguientes se instalan desde la propia app (menú
  CleanUninstall > Buscar actualizaciones…) y ya no piden este permiso.

  Atajo si prefieres la Terminal, hace lo mismo de una vez:
     xattr -cr "/Applications/CleanUninstall.app"

PARA QUE ENCUENTRE TODO
  Ajustes del Sistema > Privacidad y Seguridad > Acceso total al disco
  y activa CleanUninstall.

QUÉ HACE
  • Arrastras una app y busca lo que deja escondido: preferencias,
    cachés, servicios en segundo plano, ayudantes y recibos.
  • Lo manda a la Papelera. Nada se borra de verdad.
  • Lo de otras apps y lo de macOS no se toca.

REQUISITOS
  Mac con Apple Silicon y macOS 14 o superior.
TXT

echo "==> Configurando vista del Finder (mismo layout que las otras apps)"
osascript <<EOF
tell application "Finder"
    tell disk "$VOL"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 108
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "CleanUninstall.app" of container window to {165, 245}
        set position of item "Applications" of container window to {495, 245}
        set position of item "LÉEME.txt" of container window to {330, 400}
        set the bounds of container window to {200, 100, 860, 663}
        update without registering applications
        delay 1
        set the bounds of container window to {200, 100, 860, 663}
        update without registering applications
        delay 2
        close
        open
        delay 2
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

echo "==> Desmontando"
sync
sleep 2
hdiutil detach "$MNT"

echo "==> Comprimiendo a UDZO"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -f "$TMP_DMG"

echo "==> Listo:"
ls -lh "$OUT"
