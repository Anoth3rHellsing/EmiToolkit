#!/bin/sh
# shellcheck disable=SC2016,SC2012  # los sh -c llevan comillas simples a propósito
# Pruebas de Another's Toolbox para Mac, pensadas para correr en Linux (o en
# un Mac) sin tocar nada real: crean una carpeta personal falsa, ponen delante
# en el PATH unos comandos simulados (tmutil, xcrun, brew, docker, osascript,
# sw_vers, plutil, y stat/date con las opciones BSD) y comprueban que:
#   - el análisis y el JSON no cambian nada;
#   - la limpieza solo mueve a la Papelera lo que se ha contestado que sí;
#   - nombres con espacios, comillas y saltos de línea funcionan;
#   - los enlaces simbólicos que salen de la carpeta no se siguen;
#   - las rutas con «..» o fuera de la raíz se rechazan;
#   - nada fuera de las raíces cambia (lista de sumas antes/después).
# Uso: sh mac/pruebas/correr.sh            (con dash y bash si están)
#      SHELLS="zsh" sh mac/pruebas/correr.sh

AQUI=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$AQUI/../another-toolbox.sh"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/atb-pruebas.XXXXXX") || exit 1
if [ "${ATB_CONSERVAR:-0}" = 1 ]; then echo "(se conserva $BASE)"; else
  trap 'chmod -R u+w "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
fi

FALLOS=0; OK=0
bien() { OK=$((OK + 1)); printf '  ok   %s\n' "$1"; }
mal() { FALLOS=$((FALLOS + 1)); printf '  FALLO %s\n' "$1"; }
comprobar() { # descripción, luego la orden
  d=$1; shift
  if "$@"; then bien "$d"; else mal "$d"; fi
}

# ----------------------------------------------------------- comandos falsos --
STUBS="$BASE/stubs"; mkdir -p "$STUBS"
REAL_STAT=$(command -v stat); REAL_DATE=$(command -v date)
cat >"$STUBS/stat" <<EOF
#!/bin/sh
# stat -f FORMATO archivo (BSD) sobre el stat de GNU
if [ "\$1" = -f ]; then
  case \$2 in
    %m) exec "$REAL_STAT" -c %Y "\$3" ;;
    %z) exec "$REAL_STAT" -c %s "\$3" ;;
  esac
fi
exec "$REAL_STAT" "\$@"
EOF
cat >"$STUBS/date" <<EOF
#!/bin/sh
# date -r SEGUNDOS +FORMATO (BSD) sobre el date de GNU
if [ "\$1" = -r ]; then
  case \$2 in *[!0-9]*|'') ;; *) s=\$2; shift 2; exec "$REAL_DATE" -d "@\$s" "\$@" ;; esac
fi
exec "$REAL_DATE" "\$@"
EOF
for c in tmutil xcrun xcode-select brew docker sudo pnpm go; do
  cat >"$STUBS/$c" <<'EOF'
#!/bin/sh
n=${0##*/}
printf '%s %s\n' "$n" "$*" >>"$ATB_STUB_LOG"
case "$n $*" in
  "tmutil listlocalsnapshots /") printf 'Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-20-101010.local\ncom.apple.TimeMachine.2026-11-21-080000.local\n' ;;
  "xcode-select -p") echo /Applications/Xcode.app/Contents/Developer ;;
  "brew --cache") echo "$HOME/Library/Caches/Homebrew" ;;
  "brew cleanup -n") echo "==> This operation would free approximately 1.5GB of disk space." ;;
  "docker info") exit 0 ;;
  "docker system df") printf 'TYPE   TOTAL  SIZE\nImages 3      2.1GB\n' ;;
esac
exit 0
EOF
done
cat >"$STUBS/sw_vers" <<'EOF'
#!/bin/sh
echo 15.1
EOF
cat >"$STUBS/plutil" <<'EOF'
#!/bin/sh
# plutil -extract CLAVE raw -o - archivo: lee «CLAVE=valor» del falso Info.plist
k=$2; f=$6
sed -n "s/^$k=//p" "$f"
EOF
# osascript: por defecto falla (como si se negara el permiso de automatización)
# y obliga a usar mv; con ATB_STUB_FINDER=1 imita a Finder moviendo a ~/.Trash.
cat >"$STUBS/osascript" <<'EOF'
#!/bin/sh
printf 'osascript %s\n' "$2" | tr '\n' ' ' >>"$ATB_STUB_LOG"; echo >>"$ATB_STUB_LOG"
[ "${ATB_STUB_FINDER:-0}" = 1 ] || { echo "Not authorized to send Apple events to Finder." >&2; exit 1; }
d="$HOME/.Trash/${2##*/}"; [ -e "$d" ] && d="$d finder"
mv "$2" "$d"
EOF
chmod +x "$STUBS"/*

# ------------------------------------------------------- carpeta personal falsa --
crear_home() {
  H=$1
  mkdir -p "$H/Library/Caches/com.apple.Safari" "$H/Library/Caches/Homebrew/downloads" \
    "$H/Library/Caches/App Con Espacios" "$H/Library/Caches/trampa" "$H/Library/Caches/.oculto" \
    "$H/Library/Caches/comillas \"raras\" 'y' \$(echo no)" \
    "$H/Library/Logs/DiagnosticReports" "$H/Library/Logs/AnotherToolbox" \
    "$H/Library/Developer/Xcode/DerivedData/Proyecto-abc" "$H/Library/Developer/Xcode/Archives/2025-01-01" \
    "$H/Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)" "$H/Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)" \
    "$H/Library/Developer/CoreSimulator/Devices/ABC" \
    "$H/Library/Application Support/MobileSync/Backup/00008030-AAAA" \
    "$H/.npm/_cacache/content-v2" "$H/Downloads/sub" "$H/.Trash" \
    "$H/Library/Messages/Attachments/ab" "$H/Documents"
  mkdir -p "$H/Library/Caches/con
salto"
  dd if=/dev/zero of="$H/Library/Caches/App Con Espacios/blob" bs=1024 count=3000 2>/dev/null
  dd if=/dev/zero of="$H/Library/Caches/con
salto/f" bs=1024 count=500 2>/dev/null
  echo x >"$H/Library/Caches/comillas \"raras\" 'y' \$(echo no)/f"
  echo x >"$H/Library/Caches/.oculto/f"
  echo apple >"$H/Library/Caches/com.apple.Safari/Cache.db"
  echo brew >"$H/Library/Caches/Homebrew/downloads/x.tar.gz"
  ln -s "$OUT" "$H/Library/Caches/escape"
  ln -s "$OUT/secreto.txt" "$H/Library/Caches/trampa/enlace"
  echo crash >"$H/Library/Logs/DiagnosticReports/App.ips"
  echo propio >"$H/Library/Logs/AnotherToolbox/anterior.log"
  echo d >"$H/Library/Developer/Xcode/DerivedData/Proyecto-abc/x"
  echo a >"$H/Library/Developer/Xcode/Archives/2025-01-01/x"
  echo 17 >"$H/Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)/x"
  echo 18 >"$H/Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)/x"
  echo s >"$H/Library/Developer/CoreSimulator/Devices/ABC/x"
  printf 'Device Name=iPhone de Prueba\nLast Backup Date=2026-10-02T10:00:00Z\n' \
    >"$H/Library/Application Support/MobileSync/Backup/00008030-AAAA/Info.plist"
  echo n >"$H/.npm/_cacache/content-v2/x"
  dd if=/dev/zero of="$H/Downloads/sub/grande con espacio.dmg" bs=1024 count=103000 2>/dev/null
  echo pequeño >"$H/Downloads/pequeño.txt"
  echo basura >"$H/.Trash/viejo.txt"
  echo foto >"$H/Library/Messages/Attachments/ab/IMG_0001.HEIC"
  echo mio >"$H/Documents/tesis.docx"
}

suma() { # lista estable de rutas y sumas de un árbol (sin seguir enlaces)
  (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort) 2>/dev/null
}

# ------------------------------------------------------------------- pruebas --
probar_con() {
  SH=$1
  printf '\n== Con %s ==\n' "$SH"
  R="$BASE/$(printf '%s' "$SH" | tr -c 'a-z0-9' '_')"
  OUT="$R/fuera"; APPS="$R/Applications"; H="$R/home"; T="$R/tmp"
  mkdir -p "$OUT/logs-falsos" "$APPS/Install macOS Sonoma.app/Contents" "$APPS/Safari.app" "$T"
  echo "no me toques" >"$OUT/secreto.txt"
  echo l >"$OUT/logs-falsos/importante.log"
  echo inst >"$APPS/Install macOS Sonoma.app/Contents/x"
  echo saf >"$APPS/Safari.app/x"
  crear_home "$H"
  export ATB_STUB_LOG="$R/stub.log"; : >"$ATB_STUB_LOG"
  correr() { HOME="$H" TMPDIR="$T" PATH="$STUBS:$PATH" ATB_APLICACIONES="$APPS" \
    ATB_LOGS_SISTEMA="$R/no-existe" $SH "$SCRIPT" "$@"; }

  suma "$OUT" >"$R/fuera.antes"; suma "$H" >"$R/home.antes"; suma "$APPS" >"$R/apps.antes"

  # 1. Análisis
  correr >"$R/analisis.txt" 2>"$R/analisis.err"; rc=$?
  comprobar "el análisis termina bien" [ $rc -eq 0 ]
  comprobar "el análisis no escribe errores" [ ! -s "$R/analisis.err" ]
  for t in "Cachés de apps" "iPhone de Prueba · copia del 2026-10-02" "grande con espacio.dmg" \
           "Instaladores viejos de macOS" "2 instantánea(s)" "liberaría 1.5GB" "Images 3"; do
    comprobar "el análisis menciona «$t»" grep -qF "$t" "$R/analisis.txt"
  done
  comprobar "el análisis no tiene colores sin terminal" sh -c '! grep -q "$(printf "\033")" "$1"' sh "$R/analisis.txt"
  comprobar "la caché de Safari (com.apple.*) no se cuenta" sh -c '! grep -q "com.apple.Safari" "$1"' sh "$R/analisis.txt"
  comprobar "el análisis no cambia la carpeta personal" cmp -s "$R/home.antes" "$(suma "$H" >"$R/h1"; echo "$R/h1")"

  # 2. JSON
  correr --json >"$R/a.json" 2>"$R/json.err"
  comprobar "el JSON es válido" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$R/a.json"
  comprobar "el JSON trae las categorías esperadas" python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); ids={c["id"] for c in d["categorias"]}
need={"cache","logs","xcode-derived","copias-ios","snapshots","brew","docker","instaladores","descargas","mensajes","npm"}
sys.exit(0 if need<=ids else 1)' "$R/a.json"
  comprobar "el JSON escapa el salto de línea como ?" python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); c=[c for c in d["categorias"] if c["id"]=="cache"][0]
n=[e["nombre"] for e in c["elementos"]]
sys.exit(0 if any(x.endswith("con?salto") for x in n) and any("\"raras\"" in x for x in n) else 1)' "$R/a.json"

  # 3. Limpieza contestando NO a todo (Intro / fin de entrada)
  printf '\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | correr --limpiar >"$R/no.txt" 2>&1
  : | correr --limpiar >>"$R/no.txt" 2>&1
  suma "$H" >"$R/h2"
  comprobar "decir que no a todo no cambia nada" cmp -s "$R/home.antes" "$R/h2"
  comprobar "sin respuestas no se ejecuta ningún comando de limpieza" \
    sh -c '! grep -Eq "simctl delete|thinlocal|brew cleanup$|system prune|store prune|clean -modcache" "$1"' sh "$ATB_STUB_LOG"

  # 4. Cachés: sí a todo
  printf 's\n' | correr --limpiar --solo cache >"$R/cache.txt" 2>&1
  C="$H/Library/Caches"
  comprobar "la caché con espacios va a la Papelera" [ -f "$H/.Trash/App Con Espacios/blob" ]
  comprobar "la caché con salto de línea va a la Papelera" [ -f "$H/.Trash/con
salto/f" ]
  comprobar "la caché con comillas y \$() va a la Papelera" [ -f "$H/.Trash/comillas \"raras\" 'y' \$(echo no)/f" ]
  comprobar "la caché oculta va a la Papelera" [ -f "$H/.Trash/.oculto/f" ]
  comprobar "la carpeta con un enlace dentro se mueve con su enlace" [ -L "$H/.Trash/trampa/enlace" ]
  comprobar "com.apple.Safari se queda" [ -f "$C/com.apple.Safari/Cache.db" ]
  comprobar "Homebrew (categoría propia) se queda" [ -f "$C/Homebrew/downloads/x.tar.gz" ]
  comprobar "el enlace que sale de la carpeta se omite" [ -L "$C/escape" ]
  comprobar "el aviso del enlace sale en pantalla" grep -q "escape: es un enlace simbólico" "$R/cache.txt"
  comprobar "se intentó Finder antes que mv" grep -q '^osascript ' "$ATB_STUB_LOG"
  L=$(ls "$H/Library/Logs/AnotherToolbox/"limpieza-*.log 2>/dev/null | head -1)
  comprobar "queda registro en ~/Library/Logs/AnotherToolbox" [ -n "$L" ]
  comprobar "el registro escribe el salto de línea como \\n" grep -qF 'con\nsalto' "$L"

  # 5. Logs: el registro propio no se toca
  printf 's\n' | correr --limpiar --solo logs >"$R/logs.txt" 2>&1
  comprobar "los informes de fallos van a la Papelera" [ -f "$H/.Trash/DiagnosticReports/App.ips" ]
  comprobar "los registros de Another's Toolbox se quedan" [ -f "$H/Library/Logs/AnotherToolbox/anterior.log" ]

  # 6. DeviceSupport (con cuidado): se revisa uno a uno; no a 17, sí a 18
  printf 's\nn\ns\n' | correr --limpiar --solo xcode-devsupport >"$R/ds.txt" 2>&1
  DS="$H/Library/Developer/Xcode/iOS DeviceSupport"
  comprobar "uno a uno: 17.0 se queda (dijimos no)" [ -d "$DS/17.0 (21A329)" ]
  comprobar "uno a uno: 18.1 va a la Papelera (dijimos sí)" [ -d "$H/.Trash/18.1 (22B83)" ]

  # 7. Instaladores: uno a uno, y Safari ni se ofrece
  printf 'u\ns\n' | ATB_STUB_FINDER=1 correr --limpiar --solo instaladores >"$R/inst.txt" 2>&1
  comprobar "el instalador viejo va a la Papelera (vía Finder simulado)" [ -d "$H/.Trash/Install macOS Sonoma.app" ]
  comprobar "Safari.app no se toca ni se ofrece" sh -c '[ -f "$1/Safari.app/x" ] && ! grep -q Safari "$2"' sh "$APPS" "$R/inst.txt"

  # 8. Nombre repetido en la Papelera: nombre único y nada se pisa
  mkdir -p "$H/Library/Developer/Xcode/DerivedData/.oculto"; echo nuevo >"$H/Library/Developer/Xcode/DerivedData/.oculto/f"
  printf 's\n' | correr --limpiar --solo xcode-derived >"$R/dd.txt" 2>&1
  comprobar "el .oculto anterior de la Papelera sigue intacto" grep -qx x "$H/.Trash/.oculto/f"
  comprobar "el nuevo .oculto tiene un nombre único" sh -c 'ls -a "$1" | grep -q "^\.oculto (atb "' sh "$H/.Trash"

  # 9. Comandos oficiales: se enseñan y se ejecutan solo con sí
  : >"$ATB_STUB_LOG"
  printf 's\n' | correr --limpiar --solo simuladores >"$R/sim.txt" 2>&1
  comprobar "simuladores: ejecuta xcrun simctl delete unavailable" grep -qx 'xcrun simctl delete unavailable' "$ATB_STUB_LOG"
  comprobar "simuladores: no borra la carpeta a mano" [ -f "$H/Library/Developer/CoreSimulator/Devices/ABC/x" ]
  printf 's\n\n' | correr --limpiar --solo snapshots >"$R/tm.txt" 2>&1
  comprobar "instantáneas: tmutil thinlocalsnapshots / 999999999999 4" grep -qx 'tmutil thinlocalsnapshots / 999999999999 4' "$ATB_STUB_LOG"
  printf 's\n20\n' | correr --limpiar --solo snapshots >>"$R/tm.txt" 2>&1
  comprobar "instantáneas: 20 GB son 20000000000 bytes" grep -qx 'tmutil thinlocalsnapshots / 20000000000 4' "$ATB_STUB_LOG"
  printf 's\n' | correr --limpiar --solo brew >"$R/brew.txt" 2>&1
  comprobar "brew: ejecuta brew cleanup" grep -qx 'brew cleanup' "$ATB_STUB_LOG"
  printf 'n\n' | correr --limpiar --solo docker >"$R/dock.txt" 2>&1
  comprobar "docker: con no, no hay prune" sh -c '! grep -q "system prune" "$1"' sh "$ATB_STUB_LOG"
  printf 'si\n' | correr --limpiar --solo docker >>"$R/dock.txt" 2>&1
  comprobar "docker: con sí, docker system prune (sin -a ni --volumes)" grep -qx 'docker system prune' "$ATB_STUB_LOG"
  comprobar "nunca se llama a sudo" sh -c '! grep -q "^sudo" "$1"' sh "$ATB_STUB_LOG"

  # 10. Lo que es «solo revisar» nunca se toca, aunque se diga que sí a todo
  yes s 2>/dev/null | head -200 | correr --limpiar >"$R/todo.txt" 2>&1
  comprobar "las copias de iPhone siguen ahí" [ -f "$H/Library/Application Support/MobileSync/Backup/00008030-AAAA/Info.plist" ]
  comprobar "los adjuntos de Mensajes siguen ahí" [ -f "$H/Library/Messages/Attachments/ab/IMG_0001.HEIC" ]
  comprobar "las Descargas siguen ahí" [ -f "$H/Downloads/sub/grande con espacio.dmg" ]
  comprobar "Documentos sigue ahí" [ -f "$H/Documents/tesis.docx" ]
  comprobar "la Papelera no se vacía" [ -f "$H/.Trash/viejo.txt" ]

  # 11. Filtro de rutas
  CR="$H/Library/Caches"
  rechaza() { if correr --comprobar-ruta "$1" "$2" >"$R/cr.txt" 2>&1; then return 1; fi; return 0; }
  acepta() { correr --comprobar-ruta "$1" "$2" >"$R/cr.txt" 2>&1; }
  comprobar "rechaza «..»" rechaza "$CR" "$CR/../Documents"
  comprobar "explica el motivo del «..»" grep -q 'contiene «..»' "$R/cr.txt"
  comprobar "rechaza «..» en medio aunque empiece por la raíz" rechaza "$CR" "$CR/x/../../../Documents"
  comprobar "rechaza una ruta fuera de la raíz" rechaza "$CR" "$H/Documents/tesis.docx"
  comprobar "rechaza un prefijo parecido (Caches-otra)" rechaza "$CR" "$CR-otra"
  comprobar "rechaza lo que no es hijo directo" rechaza "$CR" "$CR/com.apple.Safari/Cache.db"
  comprobar "rechaza un enlace simbólico" rechaza "$CR" "$CR/escape"
  comprobar "rechaza una raíz que no está en la lista" rechaza "$H/Documents" "$H/Documents/tesis.docx"
  comprobar "rechaza la propia raíz" rechaza "$CR" "$CR/"
  comprobar "acepta un hijo normal" acepta "$CR" "$CR/com.apple.Safari"

  # 12. Una raíz que es un enlace a otro sitio: no se mide ni se limpia
  mv "$H/Library/Logs" "$R/logs-reales"; ln -s "$OUT/logs-falsos" "$H/Library/Logs"
  printf 's\ns\n' | correr --limpiar --solo logs >"$R/logsym.txt" 2>&1
  correr --solo logs >"$R/logsym-a.txt" 2>&1
  comprobar "raíz enlazada: se avisa" grep -q "enlace simbólico a otro sitio" "$R/logsym-a.txt"
  comprobar "raíz enlazada: lo de fuera sigue ahí" [ -f "$OUT/logs-falsos/importante.log" ]
  rm "$H/Library/Logs"; mv "$R/logs-reales" "$H/Library/Logs"

  # 13. Nada fuera de las raíces ha cambiado
  suma "$OUT" >"$R/fuera.despues"
  comprobar "la carpeta de fuera está idéntica" cmp -s "$R/fuera.antes" "$R/fuera.despues"
  suma "$APPS" | grep -v 'Install macOS' >"$R/apps.despues"; grep -v 'Install macOS' "$R/apps.antes" >"$R/apps.antes2"
  comprobar "Aplicaciones idéntica salvo el instalador" cmp -s "$R/apps.antes2" "$R/apps.despues"
  # En la carpeta personal solo pueden haber cambiado las raíces de limpieza,
  # la Papelera y el registro propio.
  filtrar() { grep -Ev '^(\./|[0-9]+ [0-9]+ \./)(\.Trash|Library/Caches|Library/Logs|Library/Developer/Xcode/(DerivedData|iOS DeviceSupport|Archives|watchOS DeviceSupport)|\.npm/_cacache)(/|$)' "$1" |
    grep -Ev '^(\./|[0-9]+ [0-9]+ \./)salto(/f)?$' ; }  # resto del nombre con salto de línea
  filtrar "$R/home.antes" >"$R/h.a"; suma "$H" >"$R/h.d0"; filtrar "$R/h.d0" >"$R/h.d"
  comprobar "fuera de las raíces, la carpeta personal está idéntica" cmp -s "$R/h.a" "$R/h.d"
  [ $FALLOS -gt 0 ] && diff "$R/h.a" "$R/h.d" | head -20
}

SHELLS=${SHELLS:-}
if [ -z "$SHELLS" ]; then
  for s in dash bash zsh; do command -v $s >/dev/null 2>&1 && SHELLS="$SHELLS $s"; done
  [ -n "$SHELLS" ] || SHELLS="sh"
fi
for s in $SHELLS; do
  case $s in zsh) probar_con "zsh --emulate sh" ;; bash) probar_con "bash --posix" ;; *) probar_con "$s" ;; esac
done
if command -v shellcheck >/dev/null 2>&1; then
  printf '\n== shellcheck ==\n'
  if shellcheck -s sh "$SCRIPT" "$AQUI/../Another Toolbox.command" "$AQUI/correr.sh"; then bien "shellcheck sin avisos"; else mal "shellcheck"; fi
else
  printf '\n(shellcheck no está instalado: pip install shellcheck-py)\n'
fi
printf '\n%s correctas, %s fallos\n' "$OK" "$FALLOS"
[ $FALLOS -eq 0 ]
