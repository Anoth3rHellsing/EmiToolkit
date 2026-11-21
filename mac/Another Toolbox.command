#!/bin/sh
# Another's Toolbox para Mac · lanzador
# Doble clic en Finder: abre Terminal y enseña un menú. Si macOS dice que no
# puede abrirlo, mira «Primera vez» en LEEME.md (clic derecho > Abrir).
cd "$(dirname "$0")" || exit 1
HERR="./another-toolbox.sh"

while :; do
  printf '\n  \033[1mAnother'"'"'s Toolbox para Mac\033[0m\n\n'
  printf '  1. Analizar qué ocupa espacio (no cambia nada)\n'
  printf '  2. Limpiar, preguntando por cada cosa (va a la Papelera)\n'
  printf '  3. Salir\n\n'
  printf '  Elige [1-3]: '
  IFS= read -r op || op=3
  case $op in
    1) /bin/sh "$HERR" ;;
    2) /bin/sh "$HERR" --limpiar ;;
    *) break ;;
  esac
done
printf '\n  Puedes cerrar esta ventana.\n\n'
