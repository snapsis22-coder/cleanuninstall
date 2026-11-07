#!/bin/zsh
# Compila CleanUninstall (antes Triturador), arma el bundle .app, lo firma e instala en /Applications.
# Molde tomado de ~/Developer/SubFix/build_app.sh.
set -e

cd "$(dirname "$0")"
PROYECTO="$PWD"
NOMBRE_APP="CleanUninstall"
PRODUCTO="Triturador"
DESTINO="/Applications/${NOMBRE_APP}.app"
IDENTIDAD="snapsis-dev"

echo "▸ Compilando…"
swift build -c release --product "$PRODUCTO"

echo "▸ Armando el bundle…"
BUNDLE="$PROYECTO/.build/${NOMBRE_APP}.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$PROYECTO/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$PROYECTO/.build/release/$PRODUCTO" "$BUNDLE/Contents/MacOS/$NOMBRE_APP"
[ -f "$PROYECTO/Resources/AppIcon.icns" ] && cp "$PROYECTO/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"
# Sin una carpeta «es.lproj» macOS pinta los menús estándar en inglés.
cp -R "$PROYECTO/Resources/es.lproj" "$BUNDLE/Contents/Resources/"

# Con firma estable (no ad-hoc) los permisos de TCC —«Acceso total al disco» incluido—
# sobreviven al rebuild. `security find-identity` NO sirve para decidirlo (puede decir
# «0 valid identities» aunque codesign sepa firmar): la única prueba fiable es firmar de verdad.
SONDA="$(mktemp -d)"
cp /bin/echo "$SONDA/sonda"
if codesign --force --sign "$IDENTIDAD" "$SONDA/sonda" >/dev/null 2>&1; then
    SIGN="$IDENTIDAD"
    echo "  firmando con '$IDENTIDAD' — los permisos sobreviven al rebuild"
else
    SIGN="-"
    echo "  ⚠ No pude firmar con '$IDENTIDAD' — firma ad-hoc, se pierden los permisos ya concedidos."
fi
rm -rf "$SONDA"

# xattr -cr es obligatorio antes de firmar, o codesign falla con "detritus not allowed".
firmar() {
    xattr -cr "$1"
    codesign --force --sign "$SIGN" "$1"
    codesign --verify --deep --strict "$1"
}

if [[ "$1" == "--sin-instalar" ]]; then
    echo "▸ Firmando en el sitio…"
    firmar "$BUNDLE" || echo "  ⚠ La firma no verifica"
    echo "✓ Bundle listo (sin instalar): $BUNDLE"
    exit 0
fi

echo "▸ Instalando en $DESTINO…"
rm -rf "$DESTINO"
cp -R "$BUNDLE" "$DESTINO"

echo "▸ Firmando lo instalado…"
firmar "$DESTINO"

echo "✓ Listo: $DESTINO"
