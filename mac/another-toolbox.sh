#!/bin/sh
# Another's Toolbox para Mac
# Analiza qué llena «Datos del sistema» (Ajustes > General > Almacenamiento)
# y, solo si se pide con --limpiar, lo manda a la Papelera categoría por
# categoría, preguntando siempre (por defecto: NO).
#
# POSIX sh puro: corre igual con el /bin/sh de macOS (bash 3.2 en modo POSIX),
# con zsh en modo sh y con dash. Solo herramientas BSD de serie (du -sk,
# find -xdev, stat -f, date -r). Sin dependencias, sin red, sin telemetría y
# sin sudo.
#
# Fuentes consultadas (nov-2026) sobre qué hay en «Datos del sistema»:
#   https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/
#   https://www.macworld.com/article/676493/how-to-delete-system-data-mac.html
#   https://support.apple.com/es-lamr/guide/mac-help/mchl3d437fbc/mac  (Almacenamiento)
# Cada categoría cita abajo su propia fuente. «No verificado en Mac» quiere
# decir que la ruta o el comando vienen de la documentación pero este script
# no se ha ejecutado todavía en un Mac real.

ATB_VERSION="1.0.0"
ATB_NOMBRE="Another's Toolbox para Mac"

# Homebrew, Docker y compañía no suelen estar en el PATH de /bin/sh cuando se
# abre desde Finder. Se añaden al final, así que lo que ya haya va primero.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin"
export PATH
HOMEBREW_NO_AUTO_UPDATE=1; HOMEBREW_NO_ANALYTICS=1; HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_ANALYTICS HOMEBREW_NO_ENV_HINTS
LC_NUMERIC=C; export LC_NUMERIC

# Rutas fuera de HOME. Solo se pueden cambiar para las pruebas automáticas.
ATB_APLICACIONES="${ATB_APLICACIONES:-/Applications}"
ATB_LOGS_SISTEMA="${ATB_LOGS_SISTEMA:-/Library/Logs}"

NL='
'
TAB=$(printf '\t')

# ---------------------------------------------------------------- opciones --
MODO=analizar
SOLO=""
COLOR=auto
uso() {
  cat <<EOF
$ATB_NOMBRE $ATB_VERSION

Uso: another-toolbox.sh [opciones]

  (sin opciones)     analiza y enseña qué ocupa espacio. No cambia nada.
  --limpiar          repasa cada categoría y pregunta antes de tocar nada.
                     Lo que se quita va a la Papelera (se puede recuperar).
  --json             el análisis en JSON (para una futura interfaz gráfica).
  --solo ID[,ID]     solo esas categorías (los ID salen en el análisis).
  --sin-color        sin colores.
  --ayuda            esta ayuda.

Registro de lo movido: ~/Library/Logs/AnotherToolbox/
EOF
}
while [ $# -gt 0 ]; do
  case $1 in
    --limpiar|--clean) MODO=limpiar ;;
    --json) MODO=json ;;
    --solo) shift; SOLO=${1:-} ;;
    --solo=*) SOLO=${1#--solo=} ;;
    --sin-color|--no-color) COLOR=no ;;
    --ayuda|--help|-h) uso; exit 0 ;;
    --comprobar-ruta)
      # Solo para las pruebas: dice si una ruta pasaría el filtro de seguridad.
      MODO=comprobar; CR_RAIZ=${2:-}; CR_RUTA=${3:-}; shift 2 ;;
    *) printf 'Opción desconocida: %s\n\n' "$1" >&2; uso >&2; exit 2 ;;
  esac
  shift
done

if [ "$COLOR" = auto ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$MODO" != json ]; then
  C_B=$(printf '\033[1m'); C_D=$(printf '\033[2m'); C_R=$(printf '\033[0m')
  C_VE=$(printf '\033[32m'); C_AM=$(printf '\033[33m'); C_RO=$(printf '\033[31m')
  C_AZ=$(printf '\033[36m')
else
  C_B=""; C_D=""; C_R=""; C_VE=""; C_AM=""; C_RO=""; C_AZ=""
fi

# --------------------------------------------------------------- utilidades --
# Tamaños: du -k cuenta bloques de 1024 bytes; se enseñan en unidades de 1000
# como hace Finder desde Mac OS X 10.6, con coma decimal.
legible() {
  awk -v k="${1:-0}" 'BEGIN {
    b = k * 1024
    if (b >= 1e12) printf "%.1f TB", b / 1e12
    else if (b >= 1e9) printf "%.1f GB", b / 1e9
    else if (b >= 1e6) printf "%.1f MB", b / 1e6
    else if (b >= 1e3) printf "%.0f KB", b / 1e3
    else if (b > 0) printf "%d B", b
    else printf "0"
  }' | tr '.' ','
}

# Una ruta para enseñar en pantalla: sin saltos de línea ni tabuladores, y con
# ~ en lugar de la carpeta personal.
mostrar() {
  case $1 in
    "$HOME"/*) m=\~/${1#"$HOME"/} ;;
    *) m=$1 ;;
  esac
  printf '%s' "$m" | tr '\n\t' '??'
}

# Cadena JSON (sin las comillas de fuera).
json_txt() {
  printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | awk '
    BEGIN { ORS = "" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
      if (NR > 1) print "\\n"; print }'
}

# Tamaño en KB de una ruta sin seguir enlaces ni cruzar volúmenes.
# Deja en DU_RC el código de salida (≠0 si faltó permiso para algo).
du_kb() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then DU_KB=0; DU_RC=0; return; fi
  DU_OUT=$(du -skx "$1" 2>/dev/null); DU_RC=$?
  DU_KB=${DU_OUT%%[!0-9]*}
  [ -n "$DU_KB" ] || DU_KB=0
}

fecha_de() { # epoch -> AAAA-MM-DD (date -r es BSD)
  date -r "$1" '+%Y-%m-%d' 2>/dev/null || printf '?'
}
mtime_de() { stat -f %m "$1" 2>/dev/null || printf '0'; }

hay() { command -v "$1" >/dev/null 2>&1; }

# ¿Coincide el nombre con alguno de los patrones (separados por ':')?
coincide() {
  co_nombre=$1; co_lista=$2
  [ -n "$co_lista" ] || return 1
  set -f; co_ifs=$IFS; IFS=:
  for co_pat in $co_lista; do
    # shellcheck disable=SC2254
    case $co_nombre in $co_pat) IFS=$co_ifs; set +f; return 0 ;; esac
  done
  IFS=$co_ifs; set +f
  return 1
}

# Ruta física (sin enlaces) de un directorio, o vacío si no se puede.
fisica() { (cd -P "$1" 2>/dev/null && pwd -P); }

HOME_F=$(fisica "$HOME")
if [ -z "$HOME_F" ]; then
  echo "No encuentro la carpeta personal (HOME=$HOME)." >&2; exit 1
fi

# Una raíz es válida si existe, es un directorio de verdad (no un enlace) y
# ninguna carpeta de su camino es un enlace que la lleve a otra parte.
raiz_valida() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  case $1 in */../*|*/..|*/./*) return 1 ;; esac
  rv_f=$(fisica "$1")
  case $1 in
    "$HOME"/*) [ "$rv_f" = "$HOME_F/${1#"$HOME"/}" ] ;;
    *) [ "$rv_f" = "$1" ] ;;
  esac
}

# El filtro por el que pasa todo lo que se va a mover:
#  - sin componentes «..»;
#  - hijo directo de su raíz (nada de rutas que se salgan);
#  - la raíz está en la lista de raíces permitidas y es válida;
#  - no es un enlace simbólico (se omite: no se sigue ni se mueve).
RAICES_PERMITIDAS=""
ruta_segura() {
  rs_raiz=$1; rs_ruta=$2
  case "/$rs_raiz/" in */../*) RS_MOTIVO="la raíz contiene «..»"; return 1 ;; esac
  case "/$rs_ruta/" in */../*) RS_MOTIVO="la ruta contiene «..»"; return 1 ;; esac
  case $rs_ruta in
    "$rs_raiz"/?*) : ;;
    *) RS_MOTIVO="está fuera de $(mostrar "$rs_raiz")"; return 1 ;;
  esac
  rs_resto=${rs_ruta#"$rs_raiz"/}
  case $rs_resto in */*) RS_MOTIVO="no es un elemento directo de la carpeta"; return 1 ;; esac
  case $rs_resto in .|..) RS_MOTIVO="nombre reservado"; return 1 ;; esac
  rs_ok=no
  rs_ifs=$IFS; IFS=$NL
  for rs_r in $RAICES_PERMITIDAS; do [ "$rs_r" = "$rs_raiz" ] && rs_ok=si; done
  IFS=$rs_ifs
  [ $rs_ok = si ] || { RS_MOTIVO="la carpeta no está en la lista permitida"; return 1; }
  raiz_valida "$rs_raiz" || { RS_MOTIVO="la carpeta es un enlace o no existe"; return 1; }
  [ -L "$rs_ruta" ] && { RS_MOTIVO="es un enlace simbólico (no se sigue)"; return 1; }
  [ -e "$rs_ruta" ] || { RS_MOTIVO="ya no existe"; return 1; }
  return 0
}

# --------------------------------------------------------------- categorías --
# id|modo|seguridad|raíz|incluir|excluir|herramienta|comando|título|qué es|cómo vuelve
#  modo: hijos   = se puede mandar a la Papelera lo que hay dentro de la raíz
#        comando = se limpia con el comando oficial (se enseña antes)
#        revisar = solo se enseña; nunca se borra
#  seguridad: seguro | cuidado | revisar
# Patrones de incluir/excluir separados por ':'.
DEV="$HOME/Library/Developer"
CATS="\
cache|hijos|seguro|$HOME/Library/Caches||com.apple.*:CloudKit:FamilyCircle:Homebrew:pip:Yarn:pnpm:AnotherToolbox|||Cachés de apps|Copias temporales que guardan las apps para ir más rápido (no las de macOS, que no se tocan).|Cada app las vuelve a crear al abrirse. Cierra las apps antes de limpiar.
logs|hijos|seguro|$HOME/Library/Logs||AnotherToolbox|||Registros (logs) del usuario|Registros de apps e informes de fallos (DiagnosticReports).|Las apps escriben registros nuevos; los viejos no hacen falta salvo para depurar un fallo.
syslogs|revisar|revisar|$ATB_LOGS_SISTEMA|||||Registros del sistema|Registros de /Library/Logs (solo la parte que se puede leer sin administrador).|macOS los rota solo. No se tocan: harían falta permisos de administrador.
xcode-derived|hijos|seguro|$DEV/Xcode/DerivedData|||||Xcode · DerivedData|Compilaciones intermedias e índices de Xcode.|Xcode lo regenera al compilar; la primera compilación será más lenta.
xcode-archives|hijos|cuidado|$DEV/Xcode/Archives|||||Xcode · Archives|Archivos de apps publicadas, con los dSYM para descifrar informes de fallos.|No se regeneran. Quita solo los de versiones que ya no soportas.
xcode-devsupport|hijos|cuidado|$DEV/Xcode/iOS DeviceSupport|||||Xcode · iOS DeviceSupport|Símbolos copiados de cada versión de iOS de los dispositivos que conectaste.|Xcode los vuelve a copiar al conectar un dispositivo con esa versión. Conserva las versiones que uses.
xcode-watchsupport|hijos|cuidado|$DEV/Xcode/watchOS DeviceSupport|||||Xcode · watchOS DeviceSupport|Símbolos de cada versión de watchOS.|Xcode los vuelve a copiar al conectar el reloj.
simuladores|comando|seguro|$DEV/CoreSimulator|||xcrun|xcrun simctl delete unavailable|Simuladores de iOS|Dispositivos simulados de Xcode. El comando quita solo los que ya no tienen sistema instalado.|Los simuladores que borra no se pueden usar con tu Xcode actual. Los runtimes se gestionan en Xcode > Ajustes > Componentes.
copias-ios|revisar|revisar|$HOME/Library/Application Support/MobileSync/Backup|||||Copias de iPhone/iPad|Copias de seguridad locales de tus dispositivos.|NO se regeneran: borrarlas es perderlas. Gestiónalas desde Finder.
snapshots|comando|seguro|/|||tmutil|tmutil thinlocalsnapshots / BYTES 4|Instantáneas locales de Time Machine|Copias APFS que Time Machine guarda en el propio disco hasta poder copiarlas al disco de copia.|macOS las borra solo cuando falta espacio. Quitarlas pierde esos puntos de restauración locales, no las copias del disco externo.
brew|comando|seguro||||brew|brew cleanup|Caché de Homebrew|Descargas y versiones antiguas de paquetes de Homebrew.|Homebrew vuelve a descargar lo que haga falta.
npm|hijos|seguro|$HOME/.npm/_cacache|||||Caché de npm|Paquetes descargados por npm (equivale a «npm cache clean --force»).|npm los vuelve a descargar.
yarn|hijos|seguro|$HOME/Library/Caches/Yarn|||||Caché de Yarn|Paquetes descargados por Yarn.|Yarn los vuelve a descargar.
pnpm|comando|seguro|$HOME/Library/pnpm/store|||pnpm|pnpm store prune|Almacén de pnpm|Paquetes compartidos por los proyectos pnpm. Se poda con su comando para no romper proyectos.|pnpm vuelve a descargar lo que falte.
pip|hijos|seguro|$HOME/Library/Caches/pip|||||Caché de pip|Paquetes y wheels descargados por pip.|pip los vuelve a descargar.
cargo|hijos|seguro|$HOME/.cargo/registry/cache|||||Caché de Cargo (Rust)|Archivos .crate descargados.|Cargo los vuelve a descargar al compilar.
gradle|hijos|seguro|$HOME/.gradle/caches|||||Caché de Gradle|Dependencias y compilaciones en caché de Gradle/Android Studio. Cierra Android Studio antes.|Gradle lo vuelve a descargar en la siguiente compilación.
maven|hijos|cuidado|$HOME/.m2/repository|||||Repositorio local de Maven|Dependencias de Maven. Puede contener paquetes tuyos instalados con «mvn install».|Lo de Maven Central se vuelve a descargar; lo instalado a mano no.
gem|revisar|revisar|$HOME/.gem|||||Gemas de Ruby|Gemas instaladas por el usuario.|Para quitar versiones viejas: gem cleanup.
go|comando|seguro|$HOME/go/pkg/mod|||go|go clean -modcache|Módulos de Go|Caché de módulos descargados por Go.|Go los vuelve a descargar.
vscode|hijos|seguro|$HOME/Library/Application Support/Code|Cache:CachedData:CachedExtensionVSIXs:Code Cache:GPUCache:logs||||Cachés de VS Code|Cachés, extensiones descargadas y registros de Visual Studio Code. Cierra VS Code antes.|VS Code los vuelve a crear.
android-avd|revisar|revisar|$HOME/.android/avd|||||Emuladores de Android|Discos de los emuladores (AVD).|Bórralos desde Android Studio > Device Manager.
docker|comando|cuidado|$HOME/Library/Containers/com.docker.docker/Data/vms/0/data|||docker|docker system prune|Docker|Imágenes, contenedores parados, redes y caché de compilación de Docker.|Lo que se quite habrá que volver a descargarlo o construirlo. No toca volúmenes.
instaladores|hijos|seguro|$ATB_APLICACIONES|Install macOS*.app:Install OS X*.app||||Instaladores viejos de macOS|Apps «Instalar macOS …» que quedaron tras actualizar.|Se pueden volver a descargar del App Store o con softwareupdate.
descargas|revisar|revisar|$HOME/Downloads|||||Descargas grandes o viejas|Archivos de más de 100 MB de tu carpeta Descargas.|Son tuyos: revísalos tú.
papelera|revisar|revisar|$HOME/.Trash|||||Papelera|Lo que ya está en la Papelera sigue ocupando espacio.|Vacíala desde Finder cuando estés seguro.
mail|revisar|revisar|$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads|||||Adjuntos abiertos en Mail|Copias de adjuntos que abriste desde Mail.|El adjunto sigue en el correo.
mensajes|revisar|revisar|$HOME/Library/Messages/Attachments|||||Adjuntos de Mensajes|Fotos, vídeos y archivos de tus conversaciones.|NO se regeneran. Gestiónalos en Ajustes > General > Almacenamiento > Mensajes.
"
# Fuentes por categoría:
#  cache, logs: https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/
#  xcode-*, simuladores: https://developer.apple.com/forums/thread/812408 ;
#    https://www.kodeco.com/19998365-understanding-and-managing-xcode-space
#    («simctl delete unavailable» borra los dispositivos sin runtime instalado).
#  copias-ios: https://support.apple.com/108809 (~/Library/Application Support/MobileSync/Backup).
#  snapshots: man tmutil; https://eclecticlight.co/2020/01/22/time-machine-11-tmutil/ ;
#    https://eclecticlight.co/2026/09/09/take-control-of-snapshots/
#    Sintaxis «thinlocalsnapshots mount [purgeamount] [urgency 1-4]». No verificado en Mac.
#  brew: https://docs.brew.sh/Manpage («brew cleanup -n» enseña sin borrar).
#  npm/yarn/pip/cargo/gradle/maven/go/pnpm: rutas por defecto de cada herramienta
#    en macOS (documentación de cada una); no verificado en Mac.
#  docker: «docker system df» y «docker system prune» (docs.docker.com); la ruta
#    de Docker.raw es la de Docker Desktop; no verificado en Mac.
#  mail, mensajes: rutas habituales en macOS 14/15; no verificado en Mac.
#  Acceso total al disco: https://support.apple.com/es-lamr/guide/mac-help/mchlccb25729/mac

# Carga los campos de una categoría en variables K_*.
cargar() {
  cg_ifs=$IFS; IFS=$NL; set -f
  for cg_l in $CATS; do
    case $cg_l in "$1|"*)
      IFS='|'
      # shellcheck disable=SC2086
      set -- $cg_l
      K_ID=$1; K_MODO=$2; K_SEG=$3; K_RAIZ=$4; K_INC=$5; K_EXC=$6
      K_HERR=$7; K_CMD=$8; K_TIT=$9; shift 9; K_QUE=$1; K_REGEN=$2
      IFS=$cg_ifs; set +f; return 0 ;;
    esac
  done
  IFS=$cg_ifs; set +f; return 1
}
IDS=$(printf '%s' "$CATS" | sed -n 's/^\([a-z0-9-]*\)|.*/\1/p')

seleccionada() {
  [ -z "$SOLO" ] && return 0
  case ",$SOLO," in *",$1,"*) return 0 ;; esac
  return 1
}

# Todas las raíces de modo «hijos»: lo único de lo que se puede mover algo.
for _id in $IDS; do
  cargar "$_id"
  [ "$K_MODO" = hijos ] && RAICES_PERMITIDAS="$RAICES_PERMITIDAS$K_RAIZ$NL"
done

# Recorre los hijos de una raíz que cumplen incluir/excluir y llama a
# $1 con cada ruta. Los globs no parten nombres con espacios ni saltos de línea.
recorrer_hijos() {
  rh_fn=$1
  raiz_valida "$K_RAIZ" || return 0
  for rh_f in "$K_RAIZ"/* "$K_RAIZ"/.[!.]* "$K_RAIZ"/..?*; do
    [ -e "$rh_f" ] || [ -L "$rh_f" ] || continue
    rh_n=${rh_f##*/}
    case $rh_n in .DS_Store|.localized) continue ;; esac
    if [ -n "$K_INC" ] && ! coincide "$rh_n" "$K_INC"; then continue; fi
    coincide "$rh_n" "$K_EXC" && continue
    "$rh_fn" "$rh_f"
  done
}

# ------------------------------------------------------------------ análisis --
TMP=$(mktemp -d "${TMPDIR:-/tmp}/anothertoolbox.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT TERM
FDA_FALTA=no

_suma_hijo() {
  du_kb "$1"
  SH_TOTAL=$((SH_TOTAL + DU_KB))
  SH_N=$((SH_N + 1))
  [ "$DU_RC" -ne 0 ] && SH_PARCIAL=si
  if [ -L "$1" ]; then return; fi
  printf '%s\t%s\n' "$DU_KB" "$(mostrar "$1")" >>"$TMP/items.$K_ID"
}

# Deja en A_KB, A_PARCIAL, A_NOTA y $TMP/items.ID lo que encuentra.
analizar() {
  A_KB=0; A_PARCIAL=no; A_NOTA=""; A_PRESENTE=no
  : >"$TMP/items.$K_ID"
  case $K_ID in
    snapshots) analizar_snapshots; return ;;
    brew) analizar_brew; return ;;
    docker) analizar_docker; return ;;
  esac
  if [ ! -e "$K_RAIZ" ]; then return; fi
  A_PRESENTE=si
  if ! raiz_valida "$K_RAIZ"; then
    A_NOTA="La carpeta es un enlace simbólico a otro sitio: se omite por seguridad."
    return
  fi
  if ! ls "$K_RAIZ" >/dev/null 2>&1; then
    A_PARCIAL=si; FDA_FALTA=si
    A_NOTA="macOS no deja leerla sin «Acceso total al disco»."
    return
  fi
  case $K_MODO in
    hijos)
      SH_TOTAL=0; SH_N=0; SH_PARCIAL=no
      recorrer_hijos _suma_hijo
      A_KB=$SH_TOTAL; A_PARCIAL=$SH_PARCIAL
      [ "$SH_N" -eq 0 ] && A_PRESENTE=vacio ;;
    *)
      du_kb "$K_RAIZ"; A_KB=$DU_KB
      [ "$DU_RC" -ne 0 ] && A_PARCIAL=si ;;
  esac
  case $K_ID in
    copias-ios) analizar_copias ;;
    descargas) analizar_descargas ;;
    simuladores)
      if ! hay xcrun || ! xcode-select -p >/dev/null 2>&1; then
        A_NOTA="No hay herramientas de Xcode: no se ejecuta simctl."
      fi ;;
    pnpm|go) hay "$K_HERR" || A_NOTA="«$K_HERR» no está instalado: solo se informa." ;;
  esac
  [ "$A_PARCIAL" = si ] && [ -z "$A_NOTA" ] &&
    A_NOTA="Parte del contenido no se pudo leer (permisos); el tamaño real puede ser mayor."
  case $K_ID in mail|mensajes|papelera|copias-ios) [ "$A_PARCIAL" = si ] && FDA_FALTA=si ;; esac
  return 0
}

analizar_copias() {
  for ac_d in "$K_RAIZ"/*; do
    [ -d "$ac_d" ] && [ ! -L "$ac_d" ] || continue
    du_kb "$ac_d"
    ac_nom=""; ac_fec=""
    if [ -f "$ac_d/Info.plist" ] && hay plutil; then
      ac_nom=$(plutil -extract "Device Name" raw -o - "$ac_d/Info.plist" 2>/dev/null)
      ac_fec=$(plutil -extract "Last Backup Date" raw -o - "$ac_d/Info.plist" 2>/dev/null)
      ac_fec=${ac_fec%%T*}
    fi
    [ -n "$ac_nom" ] || ac_nom="(dispositivo ${ac_d##*/})"
    [ -n "$ac_fec" ] || ac_fec=$(fecha_de "$(mtime_de "$ac_d")")
    printf '%s\t%s · copia del %s\n' "$DU_KB" "$(printf '%s' "$ac_nom" | tr '\n\t' '??')" "$ac_fec" >>"$TMP/items.$K_ID"
  done
  A_NOTA="Para borrar una: conecta el dispositivo o abre Finder > (tu iPhone) > Gestionar copias de seguridad."
}

analizar_descargas() {
  : >"$TMP/items.$K_ID"
  # find -xdev no cruza volúmenes ni sigue enlaces; la salida ya va saneada.
  find "$K_RAIZ" -xdev -type f -size +100M -exec sh -c '
    r=$1; shift
    for f; do
      k=$(du -sk "$f" 2>/dev/null); k=${k%%[!0-9]*}
      m=$(stat -f %m "$f" 2>/dev/null || echo 0)
      d=$(date -r "$m" +%Y-%m-%d 2>/dev/null || echo "?")
      n=$(printf "%s" "${f#"$r"/}" | tr "\n\t" "??")
      printf "%s\t%s (%s)\n" "${k:-0}" "$n" "$d"
    done' sh "$K_RAIZ" {} + 2>/dev/null >"$TMP/desc.raw"
  # (El primer argumento del sh -c es la raíz, para quitarla del nombre.)
  grep -v "^0$TAB" "$TMP/desc.raw" >"$TMP/items.$K_ID" 2>/dev/null
  A_NOTA="Solo se listan; los archivos de Descargas son tuyos y nunca se tocan."
}

analizar_snapshots() {
  hay tmutil || return 0
  SN_OUT=$(tmutil listlocalsnapshots / 2>/dev/null)
  SN_N=$(printf '%s\n' "$SN_OUT" | grep -c 'com\.apple\.TimeMachine\.' )
  A_PRESENTE=si
  [ "$SN_N" -gt 0 ] || A_PRESENTE=vacio
  printf '%s\n' "$SN_OUT" | grep 'com\.apple\.TimeMachine\.' | sed 's/^/0	/' >"$TMP/items.$K_ID"
  A_NOTA="$SN_N instantánea(s). macOS no dice cuánto ocupan; las borra solo si hace falta espacio."
}

analizar_brew() {
  hay brew || return 0
  BR_CACHE=$(brew --cache 2>/dev/null)
  [ -n "$BR_CACHE" ] && [ -d "$BR_CACHE" ] || return 0
  A_PRESENTE=si; K_RAIZ=$BR_CACHE
  du_kb "$BR_CACHE"; A_KB=$DU_KB
  BR_LIBERA=$(brew cleanup -n 2>/dev/null | sed -n 's/.*would free approximately \([^ ]*\).*/\1/p' | tail -1)
  if [ -n "$BR_LIBERA" ]; then A_NOTA="«brew cleanup -n» calcula que liberaría $BR_LIBERA."
  else A_NOTA="«brew cleanup -n» no encuentra nada que quitar ahora."; fi
}

analizar_docker() {
  if [ -e "$K_RAIZ" ]; then
    A_PRESENTE=si
    du_kb "$K_RAIZ"; A_KB=$DU_KB
  fi
  hay docker || { [ $A_PRESENTE = si ] && A_NOTA="Docker Desktop instalado pero sin la orden docker."; return 0; }
  A_PRESENTE=si
  if docker info >/dev/null 2>&1; then
    docker system df 2>/dev/null | sed 's/^/0	/' >"$TMP/items.$K_ID"
    A_NOTA="Tamaño del disco virtual de Docker Desktop; el detalle es «docker system df»."
  else
    A_NOTA="Docker no está en marcha; ábrelo para ver el detalle y poder limpiarlo."
  fi
}

# Los elementos, de mayor a menor; las listas sin tamaños (instantáneas,
# docker system df) se dejan en su orden.
ordenar_items() {
  case $1 in
    snapshots|docker) cat "$TMP/items.$1" ;;
    *) sort -t "$TAB" -k1,1nr "$TMP/items.$1" ;;
  esac
}

etiqueta_seg() {
  case $1 in
    seguro) printf '%sSe puede quitar%s' "$C_VE" "$C_R" ;;
    cuidado) printf '%sCon cuidado%s' "$C_AM" "$C_R" ;;
    *) printf '%sSolo revisar%s' "$C_AZ" "$C_R" ;;
  esac
}

aviso_fda() {
  cat <<EOF

${C_AM}Algunas carpetas están protegidas por macOS.${C_R}
Para que Terminal pueda medirlas: menú Apple > Ajustes del Sistema >
Privacidad y seguridad > Acceso total al disco, activa «Terminal» (o añádela
con +) y vuelve a abrir Terminal. Es un permiso amplio: puedes quitarlo al
terminar. Sin él, la herramienta sigue funcionando con lo demás.
EOF
}

ejecutar_analisis() {
  : >"$TMP/orden"
  for id in $IDS; do
    seleccionada "$id" || continue
    cargar "$id"
    analizar
    {
      printf '%s\n' "$A_KB" >"$TMP/kb.$id"
      printf '%s\n' "$A_PRESENTE" >"$TMP/pres.$id"
      printf '%s\n' "$A_PARCIAL" >"$TMP/parc.$id"
      printf '%s' "$A_NOTA" >"$TMP/nota.$id"
      printf '%s' "$K_RAIZ" >"$TMP/raiz.$id"
    }
    [ "$A_PRESENTE" = no ] || printf '%s\t%s\n' "$A_KB" "$id" >>"$TMP/orden"
  done
  sort -t "$TAB" -k1,1nr "$TMP/orden" >"$TMP/orden.s"
}

salida_texto() {
  printf '\n%s%s%s %s· análisis (no se ha cambiado nada)%s\n' "$C_B" "$ATB_NOMBRE" "$C_R" "$C_D" "$C_R"
  if hay sw_vers; then printf '%smacOS %s%s\n' "$C_D" "$(sw_vers -productVersion 2>/dev/null)" "$C_R"; fi
  # Primero las columnas de ancho fijo (ASCII): printf cuenta bytes, no letras.
  printf '\n%s  #  %-10s %-16s %s%s\n' "$C_B" "Ocupa" "Se puede quitar" "Categoría  [id]" "$C_R"
  n=0; total_ok=0; total_rev=0
  while IFS="$TAB" read -r kb id; do
    n=$((n + 1)); cargar "$id"
    case $K_SEG in seguro) total_ok=$((total_ok + kb)) ;; cuidado) total_rev=$((total_rev + kb)) ;; esac
    tam=$(legible "$kb"); [ "$id" = snapshots ] && tam="?"
    [ "$(cat "$TMP/pres.$id")" = vacio ] && [ "$kb" -eq 0 ] && tam="vacio"
    # Ya rellenas a 16 letras («Sí» lleva tilde y printf contaría un byte de más).
    case $K_SEG in
      seguro) et="Sí              "; ec=$C_VE ;;
      cuidado) et="Con cuidado     "; ec=$C_AM ;;
      *) et="Solo revisar    "; ec=$C_AZ ;;
    esac
    printf ' %2d. %-10s %s%s%s %s  %s[%s]%s\n' "$n" "$tam" "$ec" "$et" "$C_R" "$K_TIT" "$C_D" "$id" "$C_R"
  done <"$TMP/orden.s"
  [ "$n" -eq 0 ] && printf '  No he encontrado nada de lo que busco.\n'

  printf '\n%sDetalle%s\n' "$C_B" "$C_R"
  while IFS="$TAB" read -r kb id; do
    cargar "$id"
    printf '\n%s%s%s  [%s]  %s\n' "$C_B" "$K_TIT" "$C_R" "$id" "$(legible "$kb")"
    r=$(cat "$TMP/raiz.$id"); [ -n "$r" ] && printf '  Dónde:   %s\n' "$(mostrar "$r")"
    printf '  Qué es:  %s\n' "$K_QUE"
    printf '  Vuelve:  %s\n' "$K_REGEN"
    case $K_MODO in
      comando) printf '  Limpiar: %s%s%s (con --limpiar; se enseña antes)\n' "$C_AZ" "$K_CMD" "$C_R" ;;
      hijos) printf '  Limpiar: a la Papelera con --limpiar, preguntando antes\n' ;;
      *) printf '  Limpiar: no lo hace esta herramienta\n' ;;
    esac
    nota=$(cat "$TMP/nota.$id"); [ -n "$nota" ] && printf '  %sNota:%s    %s\n' "$C_AM" "$C_R" "$nota"
    if [ -s "$TMP/items.$id" ]; then
      ordenar_items "$id" | head -8 | while IFS="$TAB" read -r ik inom; do
        if [ "$ik" -gt 0 ]; then printf '     %s%9s%s  %s\n' "$C_D" "$(legible "$ik")" "$C_R" "$inom"
        else printf '     %s\n' "$inom"; fi
      done
      ni=$(wc -l <"$TMP/items.$id" | tr -d ' ')
      [ "$ni" -gt 8 ] && printf '     %s… y %s más%s\n' "$C_D" "$((ni - 8))" "$C_R"
    fi
  done <"$TMP/orden.s"

  printf '\n%sResumen%s\n' "$C_B" "$C_R"
  printf '  Se puede quitar sin problema: %s%s%s\n' "$C_VE" "$(legible "$total_ok")" "$C_R"
  printf '  Con cuidado (mira antes):     %s%s%s\n' "$C_AM" "$(legible "$total_rev")" "$C_R"
  printf '  Para limpiar: %s --limpiar  (pregunta por cada categoría; todo va a la Papelera)\n' "$0"
  [ "$FDA_FALTA" = si ] && aviso_fda
  printf '\n'
}

salida_json() {
  sist=""; hay sw_vers && sist=$(sw_vers -productVersion 2>/dev/null)
  fda=true; [ "$FDA_FALTA" = si ] && fda=false
  printf '{\n  "herramienta": "%s",\n  "version": "%s",\n' "$(json_txt "$ATB_NOMBRE")" "$ATB_VERSION"
  printf '  "fecha": "%s",\n  "macos": "%s",\n  "home": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(json_txt "$sist")" "$(json_txt "$HOME")"
  printf '  "acceso_total_disco": %s,\n  "unidad": "KiB",\n  "categorias": [' "$fda"
  sep=""; tot=0
  while IFS="$TAB" read -r kb id; do
    cargar "$id"
    [ "$K_SEG" = seguro ] && tot=$((tot + kb))
    case $K_MODO in hijos) acc=papelera ;; comando) acc=comando ;; *) acc=solo_revisar ;; esac
    parc=false; [ "$(cat "$TMP/parc.$id")" = si ] && parc=true
    printf '%s\n    {"id": "%s", "titulo": "%s", "tamano_kb": %s, "tamano": "%s",' "$sep" "$id" "$(json_txt "$K_TIT")" "$kb" "$(legible "$kb")"
    printf ' "ruta": "%s", "seguridad": "%s", "accion": "%s",' "$(json_txt "$(cat "$TMP/raiz.$id")")" "$K_SEG" "$acc"
    printf ' "comando": "%s", "parcial": %s,' "$(json_txt "$K_CMD")" "$parc"
    printf ' "que_es": "%s", "regenera": "%s", "nota": "%s", "elementos": [' "$(json_txt "$K_QUE")" "$(json_txt "$K_REGEN")" "$(json_txt "$(cat "$TMP/nota.$id")")"
    isep=""
    if [ -s "$TMP/items.$id" ]; then
      ordenar_items "$id" | head -25 >"$TMP/it.j"
      while IFS="$TAB" read -r ik inom; do
        printf '%s{"tamano_kb": %s, "nombre": "%s"}' "$isep" "${ik:-0}" "$(json_txt "$inom")"
        isep=", "
      done <"$TMP/it.j"
    fi
    printf ']}'
    sep=","
  done <"$TMP/orden.s"
  printf '\n  ],\n  "total_seguro_kb": %s\n}\n' "$tot"
}

# ------------------------------------------------------------------ limpieza --
LOGDIR="$HOME/Library/Logs/AnotherToolbox"
LOG=""
ESTAMPA=$(date '+%Y%m%d-%H%M%S')
abrir_log() {
  [ -n "$LOG" ] && return
  mkdir -p "$LOGDIR" 2>/dev/null
  LOG="$LOGDIR/limpieza-$ESTAMPA.log"
  { printf '# %s %s · %s\n' "$ATB_NOMBRE" "$ATB_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '# fecha\tacción\torigen\tdestino (saltos de línea escritos como \\n)\n'; } >>"$LOG" 2>/dev/null
}
anotar() { # acción origen destino
  abrir_log
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$(json_txt "$2")" "$(json_txt "$3")" >>"$LOG" 2>/dev/null
}

# AppleScript en un archivo aparte: la ruta va como argumento, así que ningún
# nombre (comillas, saltos de línea…) puede colarse en el código.
AS="$TMP/papelera.applescript"
cat >"$AS" <<'EOF'
on run argv
	set f to POSIX file (item 1 of argv)
	tell application "Finder" to delete f
end run
EOF

PAPELERA="$HOME/.Trash"
# Manda una ruta a la Papelera. Primero con Finder (así funciona «Devolver» y
# Finder pide la contraseña si el elemento es de otro usuario); si Finder no
# puede (permiso de automatización denegado), con mv a ~/.Trash y nombre único.
# Nunca rm. No verificado en Mac: el camino de Finder.
a_papelera() {
  ap_p=$1
  if [ "${ATB_PAPELERA:-finder}" != mv ] && hay osascript; then
    if osascript "$AS" "$ap_p" >/dev/null 2>"$TMP/as.err"; then
      if [ ! -e "$ap_p" ] && [ ! -L "$ap_p" ]; then
        anotar papelera-finder "$ap_p" "$PAPELERA"; return 0
      fi
    else
      # Sin permiso para controlar Finder: no se vuelve a intentar en cada
      # elemento. Se avisa una vez y se sigue con mv.
      ATB_PAPELERA="mv"
      printf '  %sFinder no ha dejado usarlo%s (Ajustes > Privacidad y seguridad > Automatización).\n' "$C_AM" "$C_R"
      printf '  Se mueve a ~/.Trash directamente: en la Papelera no saldrá «Devolver»; el registro dice de dónde vino cada cosa.\n'
      anotar aviso "finder-denegado" "$(tr '\n' ' ' <"$TMP/as.err" 2>/dev/null)"
    fi
  fi
  [ -d "$PAPELERA" ] || mkdir -p "$PAPELERA" 2>/dev/null
  ap_b=${ap_p##*/}
  ap_dst="$PAPELERA/$ap_b"; ap_i=1
  while [ -e "$ap_dst" ] || [ -L "$ap_dst" ]; do
    ap_dst="$PAPELERA/$ap_b (atb $ESTAMPA-$ap_i)"; ap_i=$((ap_i + 1))
  done
  if mv -n "$ap_p" "$ap_dst" 2>"$TMP/mv.err" && [ ! -e "$ap_p" ] && [ ! -L "$ap_p" ]; then
    anotar papelera-mv "$ap_p" "$ap_dst"; return 0
  fi
  anotar error "$ap_p" "$(tr '\n' ' ' <"$TMP/mv.err" 2>/dev/null)"
  if grep -q 'Operation not permitted' "$TMP/mv.err" 2>/dev/null; then FDA_FALTA=si; fi
  return 1
}

# Lee la respuesta. Devuelve 0 = sí, 2 = uno a uno, 1 = no (lo de por defecto,
# también si se acaba la entrada).
preguntar() {
  printf '%s ' "$1"
  if ! IFS= read -r resp; then printf '\n'; return 1; fi
  [ -t 0 ] || printf '%s\n' "$resp"   # con la entrada redirigida, que se vea qué se contestó
  case $resp in
    s|S|si|Si|SI|sí|Sí|SÍ|y|Y|yes) return 0 ;;
    u|U|uno|1) return 2 ;;
    *) return 1 ;;
  esac
}

_lista_hijo() { printf '%s\n' "$1" >>"$TMP/lista"; }

limpiar_hijos() {
  if ! raiz_valida "$K_RAIZ"; then
    printf '  %sSe omite:%s la carpeta es un enlace simbólico o no existe.\n' "$C_AM" "$C_R"; return
  fi
  # La lista va en un archivo con un nombre por entrada; para no depender de
  # que no haya saltos de línea en los nombres, se recorre con el mismo glob.
  movidos=0; fallos=0; omitidos=0; kb_mov=0
  case $K_SEG in cuidado) modo_def="uno a uno" ;; *) modo_def="" ;; esac
  if [ -n "$modo_def" ]; then
    printf '  Esta categoría pide mirar cada elemento: se preguntará uno a uno.\n'
    preguntar "  ¿Revisarla? [s/N]" || { printf '  No se toca.\n'; return; }
    LH_UNO=si
  else
    preguntar "  ¿Mandar todo esto a la Papelera? [s = sí / u = uno a uno / N = no]"
    case $? in 0) LH_UNO=no ;; 2) LH_UNO=si ;; *) printf '  No se toca.\n'; return ;; esac
  fi
  recorrer_hijos _limpiar_uno
  printf '  %sHecho:%s %s elemento(s) a la Papelera (%s)' "$C_VE" "$C_R" "$movidos" "$(legible "$kb_mov")"
  [ "$omitidos" -gt 0 ] && printf ', %s omitido(s)' "$omitidos"
  [ "$fallos" -gt 0 ] && printf ', %s%s no se pudieron mover%s' "$C_RO" "$fallos" "$C_R"
  printf '.\n'
}

_limpiar_uno() {
  lu_p=$1
  if ! ruta_segura "$K_RAIZ" "$lu_p"; then
    printf '  %sOmitido%s %s: %s\n' "$C_AM" "$C_R" "$(mostrar "$lu_p")" "$RS_MOTIVO"
    anotar omitido "$lu_p" "$RS_MOTIVO"
    omitidos=$((omitidos + 1)); return
  fi
  du_kb "$lu_p"; lu_kb=$DU_KB
  if [ "$LH_UNO" = si ]; then
    preguntar "    $(mostrar "$lu_p") ($(legible "$lu_kb")) ¿a la Papelera? [s/N]" || return 0
  fi
  if a_papelera "$lu_p"; then
    movidos=$((movidos + 1)); kb_mov=$((kb_mov + lu_kb))
  else
    fallos=$((fallos + 1))
    printf '  %sNo se pudo mover%s %s\n' "$C_RO" "$C_R" "$(mostrar "$lu_p")"
  fi
}

ejecutar_cmd() { # muestra y ejecuta una orden ya separada en argumentos
  printf '  Ejecutando: %s%s%s\n' "$C_AZ" "$*" "$C_R"
  anotar comando "$*" ""
  if "$@"; then printf '  %sHecho.%s\n' "$C_VE" "$C_R"; anotar comando-ok "$*" ""
  else printf '  %sEl comando terminó con error;%s no se ha tocado nada más.\n' "$C_RO" "$C_R"; anotar comando-error "$*" ""; fi
}

limpiar_comando() {
  case $K_ID in
    simuladores)
      if ! hay xcrun || ! xcode-select -p >/dev/null 2>&1; then
        printf '  No hay herramientas de Xcode: no se hace nada.\n'; return; fi
      printf '  Se ejecutará: %sxcrun simctl delete unavailable%s\n' "$C_AZ" "$C_R"
      printf '  Quita los simuladores cuyo iOS ya no está instalado. Los demás se quedan.\n'
      preguntar "  ¿Ejecutarlo? [s/N]" && ejecutar_cmd xcrun simctl delete unavailable ;;
    snapshots)
      hay tmutil || { printf '  No está tmutil.\n'; return; }
      printf '  macOS ya las borra solo cuando falta espacio. Quitarlas ahora libera\n'
      printf '  ese espacio, pero pierdes esos puntos de restauración locales (no los\n'
      printf '  del disco de Time Machine). Se usa el comando oficial de «adelgazar»:\n'
      printf '  %stmutil thinlocalsnapshots / <bytes> 4%s  (4 = urgencia máxima)\n' "$C_AZ" "$C_R"
      preguntar "  ¿Adelgazar las instantáneas? [s/N]" || return 0
      printf '  ¿Cuántos GB liberar como mucho? [Intro = todo lo posible] '
      IFS= read -r gb || gb=""
      case $gb in ''|*[!0-9]*) bytes=999999999999 ;; *) bytes=$((gb * 1000000000)) ;; esac
      ejecutar_cmd tmutil thinlocalsnapshots / "$bytes" 4
      printf '  %sNo verificado en Mac:%s si pide permisos, la alternativa es borrarlas\n' "$C_AM" "$C_R"
      printf '  una a una con «tmutil deletelocalsnapshots FECHA» (puede pedir administrador).\n' ;;
    brew)
      hay brew || { printf '  No está Homebrew.\n'; return; }
      printf '  Se ejecutará: %sbrew cleanup%s  (quita descargas y versiones viejas)\n' "$C_AZ" "$C_R"
      printf '  Para vaciar toda la caché: brew cleanup --prune=all (no se hace aquí).\n'
      preguntar "  ¿Ejecutarlo? [s/N]" && ejecutar_cmd brew cleanup ;;
    pnpm)
      hay pnpm || { printf '  pnpm no está instalado: no se toca el almacén.\n'; return; }
      preguntar "  Se ejecutará «pnpm store prune» (quita paquetes que ningún proyecto usa). ¿Ejecutarlo? [s/N]" &&
        ejecutar_cmd pnpm store prune ;;
    go)
      hay go || { printf '  Go no está instalado: no se toca.\n'; return; }
      preguntar "  Se ejecutará «go clean -modcache». ¿Ejecutarlo? [s/N]" && ejecutar_cmd go clean -modcache ;;
    docker)
      if ! hay docker || ! docker info >/dev/null 2>&1; then
        printf '  Docker no está en marcha: no se hace nada.\n'; return; fi
      printf '  Se ejecutará: %sdocker system prune%s\n' "$C_AZ" "$C_R"
      printf '  Quita contenedores parados, redes sin usar, imágenes colgantes y la\n'
      printf '  caché de compilación. NO quita volúmenes ni imágenes en uso.\n'
      printf '  Docker volverá a pedir confirmación.\n'
      preguntar "  ¿Ejecutarlo? [s/N]" && ejecutar_cmd docker system prune ;;
  esac
}

ejecutar_limpieza() {
  printf '\n%s%s%s · limpieza\n' "$C_B" "$ATB_NOMBRE" "$C_R"
  printf 'Para cada categoría verás qué se va a hacer. Responde %ss%s para sí;\n' "$C_B" "$C_R"
  printf 'cualquier otra cosa (o Intro) es NO. Lo que se quita va a la Papelera.\n'
  printf 'Cierra las apps (Xcode, navegadores, VS Code…) antes de empezar.\n'
  while IFS="$TAB" read -r kb id <&3; do
    cargar "$id"
    [ "$K_MODO" = revisar ] && continue
    [ "$kb" -eq 0 ] && [ "$K_MODO" = hijos ] && continue
    printf '\n%s%s%s  %s  %s\n' "$C_B" "$K_TIT" "$C_R" "$(legible "$kb")" "$(etiqueta_seg "$K_SEG")"
    printf '  %s\n  %s\n' "$K_QUE" "$K_REGEN"
    r=$(cat "$TMP/raiz.$id"); [ -n "$r" ] && [ "$r" != / ] && printf '  Dónde: %s\n' "$(mostrar "$r")"
    if [ "$K_MODO" = hijos ]; then
      if [ -s "$TMP/items.$id" ]; then
        printf '  Lo más grande:\n'
        sort -t "$TAB" -k1,1nr "$TMP/items.$id" | head -5 | while IFS="$TAB" read -r ik inom; do
          printf '     %9s  %s\n' "$(legible "$ik")" "$inom"
        done
      fi
      limpiar_hijos
    else
      limpiar_comando
    fi
  done 3<"$TMP/orden.s"
  # (La tabla se lee por el descriptor 3; las preguntas, de la entrada normal,
  # que sigue siendo el teclado o lo que se le pase por la tubería.)
  printf '\n'
  if [ -n "$LOG" ]; then printf 'Registro de esta limpieza: %s\n' "$(mostrar "$LOG")"
  else printf 'No se ha cambiado nada.\n'; fi
  printf 'Lo movido está en la Papelera: si algo falta, ábrela y usa «Devolver».\n'
  printf 'El espacio se libera de verdad al vaciar la Papelera.\n'
  [ "$FDA_FALTA" = si ] && aviso_fda
  printf '\n'
}

# --------------------------------------------------------------------- main --
case $MODO in
  comprobar)
    if ruta_segura "$CR_RAIZ" "$CR_RUTA"; then echo ok; exit 0; else echo "rechazada: $RS_MOTIVO"; exit 1; fi ;;
  json) ejecutar_analisis; salida_json ;;
  limpiar)
    ejecutar_analisis; ejecutar_limpieza ;;
  *) ejecutar_analisis; salida_texto ;;
esac
