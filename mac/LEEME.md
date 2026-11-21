# Another's Toolbox para Mac

Busca la «basura» que hace crecer **Datos del sistema** en *Ajustes del Sistema >
General > Almacenamiento*: cachés, registros, instantáneas locales de Time
Machine, Xcode y sus simuladores, copias de iPhone, Docker, cachés de Homebrew,
npm, pip y compañía, instaladores viejos de macOS…

Primero **solo mira**: enseña una tabla ordenada por tamaño con qué es cada
cosa, si se puede quitar y cómo vuelve. Solo limpia si se lo pides, pregunta
por cada categoría (por defecto *No*) y lo que quita va a la **Papelera**.

Es un único script de terminal, sin instalar nada: no usa Internet, no envía
datos a ningún sitio y no usa `sudo`. (Solo Finder puede pedir tu contraseña si
mandas a la Papelera un instalador de macOS que pertenece al sistema.)

---

## Primera vez

1. Descarga la carpeta `mac/` (por ejemplo, el zip del repositorio) y ábrela.
2. Doble clic en **`Another Toolbox.command`**. Se abre Terminal con un menú.
3. Si macOS dice que *no se puede abrir porque es de un desarrollador no
   identificado* (Gatekeeper):
   - **clic derecho > Abrir**, y otra vez **Abrir** en el aviso; o
   - en macOS 15 y posteriores, si no sale esa opción: *Ajustes del Sistema >
     Privacidad y seguridad*, abajo, **Abrir igualmente**; o
   - desde Terminal, quitando la marca de cuarentena de la descarga:
     ```sh
     xattr -d com.apple.quarantine "Another Toolbox.command" another-toolbox.sh
     ```
4. Si dice que *no tienes permiso* (el zip a veces pierde el permiso de
   ejecución):
   ```sh
   chmod +x "Another Toolbox.command" another-toolbox.sh
   ```

También se puede usar directamente desde Terminal:

```sh
sh another-toolbox.sh              # analizar (no cambia nada)
sh another-toolbox.sh --limpiar    # limpiar, preguntando
sh another-toolbox.sh --json       # el análisis en JSON
sh another-toolbox.sh --solo cache,logs --limpiar   # solo esas categorías
```

Los ID de cada categoría salen entre corchetes en el análisis.

---

## Qué mira

| Categoría | Dónde | ¿Se puede quitar? | Cómo se limpia |
|---|---|---|---|
| Cachés de apps | `~/Library/Caches` (sin las de `com.apple.*` ni CloudKit) | Sí | A la Papelera |
| Registros del usuario | `~/Library/Logs` | Sí | A la Papelera |
| Registros del sistema | `/Library/Logs` | Solo revisar | No (necesitaría administrador) |
| Xcode · DerivedData | `~/Library/Developer/Xcode/DerivedData` | Sí | A la Papelera |
| Xcode · Archives | `~/Library/Developer/Xcode/Archives` | Con cuidado | Uno a uno |
| Xcode · DeviceSupport | `…/iOS DeviceSupport`, `…/watchOS DeviceSupport` | Con cuidado | Uno a uno |
| Simuladores de iOS | `~/Library/Developer/CoreSimulator` | Sí | `xcrun simctl delete unavailable` |
| Copias de iPhone/iPad | `~/Library/Application Support/MobileSync/Backup` | **Nunca** | Lista cada dispositivo y fecha; se borran desde Finder |
| Instantáneas de Time Machine | `tmutil listlocalsnapshots /` | Sí | `tmutil thinlocalsnapshots / <bytes> 4` |
| Homebrew | `brew --cache` | Sí | `brew cleanup` (antes enseña `brew cleanup -n`) |
| npm, Yarn, pip, Cargo, Gradle | sus cachés | Sí | A la Papelera |
| pnpm, Go | su almacén | Sí | `pnpm store prune`, `go clean -modcache` |
| Maven | `~/.m2/repository` | Con cuidado | Uno a uno |
| Gemas de Ruby, emuladores de Android | `~/.gem`, `~/.android/avd` | Solo revisar | No |
| VS Code | cachés de `~/Library/Application Support/Code` | Sí | A la Papelera |
| Docker | disco virtual de Docker Desktop y `docker system df` | Con cuidado | `docker system prune` (sin volúmenes), solo si dices que sí |
| Instaladores viejos de macOS | `/Applications/Install macOS *.app` | Sí | A la Papelera |
| Descargas grandes | archivos de más de 100 MB en `~/Downloads` | Solo revisar | No: son tuyos |
| Papelera | `~/.Trash` | Solo revisar | Vacíala tú desde Finder |
| Adjuntos de Mail y de Mensajes | sus carpetas | Solo revisar | No: se gestionan en Ajustes > General > Almacenamiento |

Lo que no está instalado (Xcode, Docker, Homebrew…) simplemente no aparece.

**Las instantáneas de Time Machine:** son copias que Time Machine guarda en el
propio disco mientras no puede copiar al disco de copias. macOS las borra solo
cuando falta espacio, así que suelen ser «espacio que se libera solo». macOS no
dice cuánto ocupa cada una, por eso salen con «?». Adelgazarlas pierde esos
puntos de restauración locales, no las copias del disco externo.

---

## Garantías

- **Sin `--limpiar` no cambia nada.** Ni siquiera crea el registro.
- **Siempre pregunta**, y lo que no sea *s* / *sí* es **no**. Las categorías
  «con cuidado» se repasan elemento a elemento.
- **Nunca `rm`.** Lo que se quita va a la Papelera: primero se le pide a Finder
  (así funciona *Devolver*); si Finder no deja, se mueve a `~/.Trash` con un
  nombre que no pisa nada.
- Los comandos oficiales (`brew cleanup`, `simctl`, `tmutil`, `docker`) se
  enseñan antes y solo se ejecutan con un sí.
- Solo toca lo que está **dentro de las carpetas de la tabla**: rechaza rutas
  con `..`, lo que no sea un elemento directo de esa carpeta, los enlaces
  simbólicos (no los sigue) y las carpetas que sean un enlace a otro sitio.
  No cruza a otros discos.
- No toca nunca copias de iPhone, Mensajes, Mail, Descargas ni la Papelera.
- Nombres con espacios, comillas o saltos de línea funcionan.
- Cada cosa movida queda anotada en `~/Library/Logs/AnotherToolbox/` (de dónde
  vino y adónde fue).

### «Acceso total al disco»

macOS protege algunas carpetas (Mail, Mensajes, copias de iPhone, a veces la
Papelera). Si no se pueden leer, el análisis lo dice y sigue con lo demás.
Para medirlas: *menú Apple > Ajustes del Sistema > Privacidad y seguridad >
Acceso total al disco*, activa **Terminal** (o añádela con **+**) y vuelve a
abrir Terminal. Es un permiso amplio: puedes quitarlo al terminar.

La primera vez que se manda algo a la Papelera, macOS puede preguntar si
Terminal puede **controlar Finder**. Si dices que no, se usa `mv` a `~/.Trash`.

---

## Límites

- **No verificado en un Mac todavía.** Las pruebas corren en Linux con una
  carpeta personal falsa y comandos simulados (ver abajo). Lo que solo existe
  en macOS (Finder vía `osascript`, `tmutil`, `simctl`, `plutil`, los permisos
  de privacidad) está escrito según la documentación de Apple pero sin probar.
- No mira dentro de `~/Library/Containers` de otras apps (macOS pediría permiso
  para «acceder a los datos de otras apps»), ni `/private/var`, ni la memoria
  virtual, que macOS gestiona solo.
- Los tamaños son lo que ocupa en disco (`du`), en unidades de 1000 como Finder.
  Puede no coincidir con *Almacenamiento*, que cuenta también el espacio
  «purgable».
- El espacio se libera al **vaciar la Papelera**.

---

## Pruebas

```sh
sh mac/pruebas/correr.sh
```

Crea una carpeta personal falsa con nombres difíciles, enlaces que intentan
salirse y una carpeta «de fuera» que no se puede tocar; pone delante en el PATH
versiones simuladas de `tmutil`, `xcrun`, `brew`, `docker`, `osascript`,
`plutil`, `sw_vers` y de `stat`/`date` con las opciones de BSD; y prueba el
análisis, el JSON y la limpieza contestando sí, no y uno a uno. Compara las
sumas de todo antes y después. Corre con `dash`, `bash --posix` y
`zsh --emulate sh` si están, y con `shellcheck` si está instalado
(`pip install shellcheck-py`).

## Fuentes

- Qué hay en «Datos del sistema»: [Eclectic Light](https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/),
  [Macworld](https://www.macworld.com/article/676493/how-to-delete-system-data-mac.html).
- Copias de iPhone: [Apple, 108809](https://support.apple.com/es-lamr/108809).
- Time Machine: `man tmutil`; [Eclectic Light, tmutil](https://eclecticlight.co/2020/01/22/time-machine-11-tmutil/),
  [Take control of snapshots](https://eclecticlight.co/2026/09/09/take-control-of-snapshots/).
- Xcode: [Apple Developer Forums](https://developer.apple.com/forums/thread/812408),
  [Kodeco](https://www.kodeco.com/19998365-understanding-and-managing-xcode-space).
- Homebrew: [manual de brew](https://docs.brew.sh/Manpage).
- Acceso total al disco: [Apple, Manual de uso del Mac](https://support.apple.com/es-lamr/guide/mac-help/mchlccb25729/mac).
