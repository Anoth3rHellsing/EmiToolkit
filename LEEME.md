# Another's Toolbox

Versión **0.4.0** (la misma que se ve en la barra de título; cambios en `changelog.txt`).

Aplicación de mantenimiento para Windows 11. Interfaz WPF con la transparencia
nativa del sistema (acrylic), estilo Frutiger Aero. Sin terminal, sin instalación,
sin compilar nada: es una carpeta portable. Los archivos se siguen llamando
`EmiToolkit` (`EmiToolkit.cmd`, `EmiToolkit.ps1`).

---

## Cómo se usa

Doble clic en **`EmiToolkit.cmd`** y aceptar el aviso de administrador.

La app arranca en **modo básico**, con *Inicio*, *Asistencia (AnyDesk)* y
*Another Store*. El botón **Optimizar ahora** hace todo el mantenimiento.

El interruptor **Modo avanzado** (abajo a la izquierda) despliega el resto de
apartados para ajustar cada cosa por separado.

---

## Qué hace el botón "Optimizar ahora"

Antes de empezar enseña la lista exacta de lo que va a aplicar, con el número y
el nombre de cada elemento, y avisa de lo que no se puede deshacer. No hace
nada hasta que se confirma (el botón por defecto es *Cancelar*).

En este orden, y anotando cada cambio reversible para poder deshacerlo:

1. Punto de restauración del sistema (opcional, marcado por defecto). Si no se
   puede crear, el mensaje final lo dice.
2. **Limpieza de disco**: temporales del usuario y de Windows, descargas de
   Windows Update de más de 7 días (se omite si hay un reinicio pendiente),
   Delivery Optimization, volcados, informes de error, miniaturas y cachés de
   navegadores. **No se puede deshacer.** No vacía la papelera ni toca los
   logs de Windows, Panther ni Prefetch.
3. **Optimización de Windows 11**: las 21 optimizaciones recomendadas. Quita
   Widgets, Copilot, el icono de Chat, la búsqueda web de Bing, sugerencias y
   anuncios y la sección Recomendado, desactiva Xbox Game Bar y las tareas
   programadas de rastreo, pone el menú contextual clásico, y desactiva o
   pasa a manual 12 servicios innecesarios (fax, demo de tienda, registro
   remoto, Mapas, Cartera…).
4. **Telemetría**: los 18 ajustes de privacidad recomendados (nivel mínimo por
   directiva, DiagTrack, ID de publicidad, historial de actividad, voz y
   escritura, telemetría de Edge, Copilot, Recall…).
5. **Arranque**: desactiva solo los programas conocidos como innecesarios
   (juegos, chats, lanzadores…). No toca tareas programadas, clientes de
   sincronización (OneDrive, Dropbox, Drive), actualizadores, antivirus ni
   utilidades de periféricos.
6. **Inicio rápido**: lo desactiva si estaba activo.
7. **Firewall de ESET**: aplica las reglas del KB332 (opcional).
8. **Zen Browser**: lo pone como predeterminado si está instalado (opcional).

Al terminar muestra cuánto espacio se liberó, cuántos avisos o errores hubo
(los detalles quedan en el registro) y recomienda reiniciar.

---

## Informe de salud

El botón **Informe de salud** de *Inicio* revisa el equipo **sin cambiar
nada** y genera un HTML en español con un veredicto (*bien*, *atención*,
*mal* o *no disponible*) y una línea de «qué hacer» por apartado:

- **Equipo**: edición y versión de Windows, último reinicio, reinicio
  pendiente e Inicio rápido.
- **Almacenamiento**: espacio libre de cada unidad fija (aviso por debajo del
  15 %), estado de los discos físicos (desgaste, temperatura y errores de
  lectura cuando el disco los da) y, si se marca la casilla, el análisis de
  WinSxS con DISM (tarda varios minutos).
- **Batería** (portátiles): capacidad actual frente a la de fábrica y ciclos.
- **Estabilidad**: índice de confiabilidad de los últimos 30 días, apagados
  inesperados, pantallazos azules y programas que se cierran solos.
- **Seguridad**: antivirus (Defender o el que haya, como ESET), firewall,
  BitLocker, Secure Boot, TPM, UAC y la última actualización instalada.
- **Arranque**: programas que arrancan con Windows y, si Windows la registra,
  la duración del último arranque.
- **Lo que cambió Another's Toolbox**: resumen del diario de deshacer.
- **Antes y después**: *Optimizar ahora* guarda una foto (espacio libre,
  programas de arranque, servicios…) antes y después, y el siguiente informe
  muestra la diferencia.

El informe solo lleva el nombre del equipo: ni usuarios, ni rutas, ni
números de serie. No usa la red ni carga nada externo. Se guarda en
`%ProgramData%\EmiToolkit\informes\salud-<fecha>.html` (solo administradores)
y una copia en **Documentos** del usuario que tiene la sesión abierta, que se
abre en su navegador sin permisos de administrador. Si no se puede dejar esa
copia con seguridad (escritorio remoto, Documentos en red o con un enlace),
queda solo en ProgramData y el mensaje final lo dice.

---

## Los apartados del modo avanzado

| Apartado | Para qué sirve |
|---|---|
| **Espacio en disco** | Estado de cada disco, análisis de basura con el tamaño de cada ubicación, limpieza selectiva, DISM, y un buscador de archivos y carpetas pesados. Lo borrado desde el buscador va a la papelera; lo que no puede ir (unidades de red o extraíbles, discos sin papelera, archivos por encima de la cuota) se omite y se avisa en el registro |
| **Optimizar Windows** | Las 43 optimizaciones una por una, con las recomendadas premarcadas y avisos en las opcionales |
| **Telemetría** | Los 27 ajustes de privacidad por separado, incluido el bloqueo de dominios en el archivo `hosts` |
| **Recomendaciones** | Zen Browser y uBlock Origin, comprobación de cuentas filtradas y un almacén de contraseñas cifrado con tu usuario de Windows |
| **Apps preinstaladas** | Quitar apps que vienen con Windows (antes «Debloat») y características de Windows |
| **Aplicaciones** | Las apps instaladas del usuario: desinstalar y limpiar su caché |
| **Firewall ESET** | Los 28 grupos del KB332, prueba de conexión contra los servidores de ESET, y quitar las reglas |
| **Arranque** | Todo lo que arranca con Windows (registro, carpetas de Inicio y tareas programadas) con su estado real, y se desactiva o reactiva |
| **Procesos y RAM** | Procesos agrupados por consumo, clasificados en Sistema / Telemetría / Prescindible / Normal; se pueden cerrar, y a los de Telemetría además se les puede cortar Internet |
| **Vortex** | Mods y datos de Vortex: purgar mods, borrar Vortex por completo o limpiar Skyrim (irreversible) |
| **Navegador y energía** | Zen como predeterminado, inicio rápido e hibernación |
| **Historial y deshacer** | La lista de cambios anotados (cuándo, qué y si se puede deshacer) para deshacer uno o todos, y el historial en vivo coloreado por nivel |
| **Another Store** | Desinstalar las apps de Another Suite |

Las acciones que borran o desinstalan piden confirmación con *No* por defecto, y
cada tarea termina con un resumen de avisos y errores. Las tareas largas
(mantenimiento, desinstalar apps, cerrar procesos) tienen **Cancelar** en la barra
inferior: paran al terminar el paso en curso, nunca a mitad de un cambio.

En este documento, *Registro de Windows* es la base de datos de configuración del
sistema; lo que la app va anotando se llama *historial*.

---

## Lo que NO toca

- **Transparencia y animaciones de Windows**: solo cambian si marcas a mano las
  optimizaciones opcionales que las desactivan; nunca en *Optimizar ahora*.
- **Windows Defender** y la activación de Windows.
- **Windows Update**: no se desactiva ni se pausa. *Optimizar ahora* solo borra
  descargas de su caché con más de 7 días y evita el reinicio automático con la
  sesión abierta. Retrasar las actualizaciones de calidad (*DelayUpdates*) y
  pasar Delivery Optimization a manual (*SvcDoSvc*) son opcionales y vienen
  desmarcados.
- **ESET**: `ekrn`, `egui`, `ESET VPN` y cualquier proceso o entrada de arranque
  que contenga "eset" están en la lista protegida y nunca se desactivan.
- Audio (Realtek, Nahimic, Dolby), touchpad (Synaptics, ELAN), utilidades del
  fabricante, antivirus y procesos críticos del sistema: también protegidos.
- **Zen**: si no está instalado, no se cambia nada de navegadores.

---

## Deshacer

Cada cambio del registro, servicio, tarea programada, entrada de arranque, regla
de firewall, app quitada, característica de Windows, hibernación y variable de
entorno se guarda en `%ProgramData%\EmiToolkit\undo-journal.jsonl` (una línea
por cambio) con su valor anterior y el nombre del equipo. Esa carpeta solo la
pueden escribir los administradores y SYSTEM (la herramienta fija su ACL al
arrancar). La primera vez se migra lo que hubiera en el antiguo `Data\` de la
carpeta de la app: cada entrada se valida y el original queda como `*.migrado`.

El deshacer se ejecuta como administrador, así que solo aplica lo que la
herramienta escribe de verdad: claves de registro conocidas, sus servicios, el
archivo `hosts` desde su copia protegida y sus propias reglas de firewall. Las
entradas de otro equipo o fuera de esas listas se rechazan, se anotan en el
registro y se apartan en `undo-journal.rechazadas.jsonl`.

**Historial y deshacer → Deshacer el seleccionado** deshace un solo cambio de la
lista (se niega si hay otro más reciente sobre lo mismo: primero ese).
**Deshacer todos los cambios** lo devuelve todo a su estado
original, en orden inverso. Lo que no se pueda revertir en ese momento se queda
en el diario para volver a intentarlo; lo que nunca se podrá deshacer (archivos
borrados sin copia) se avisa en el registro. Además queda el punto de
restauración del sistema.

Los archivos borrados desde el buscador van a la **papelera**, no se eliminan.

---

## Despliegue en varios equipos

La herramienta se ejecuta como **administrador** y carga su código (`Modules\`
y `UI\`) de su propia carpeta. Esa carpeta tiene que ser **modificable solo por
administradores**; si no, cualquier usuario del equipo podría cambiar un módulo
y conseguir permisos de administrador la próxima vez que alguien la abra.

Recomendado: instalarla en `%ProgramFiles%\EmiToolkit`, que ya tiene esa ACL.

```
robocopy "\\servidor\compartido\EmiToolkit" "%ProgramFiles%\EmiToolkit" /E /XD Data
```

(en una consola de administrador). Luego se ejecuta
`"%ProgramFiles%\EmiToolkit\EmiToolkit.cmd"` en cada equipo.

**No** la copies a `C:\EmiToolkit` sin más: una carpeta nueva en la raíz de
`C:\` hereda permiso de modificación para *Usuarios autenticados*, y robocopy
`/E` no copia ACL. Si aun así quieres usar esa ruta, protégela después:

```
icacls C:\EmiToolkit /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX
```

Al arrancar ya elevada, la herramienta comprueba la ACL de su carpeta, de
`Modules\`, de `UI\` y de cada archivo. Si un usuario sin privilegios puede
escribir en ellos, avisa y ofrece copiarse a `%ProgramFiles%\EmiToolkit` y
abrirse desde allí, salir o continuar (queda anotado en el registro). Los
módulos se leen una sola vez al arrancar; las tareas en segundo plano usan esa
copia en memoria.

Cada máquina guarda sus datos en `%ProgramData%\EmiToolkit` (logs
`EmiToolkit_AAAAMMDD.log`, diario y copia de `hosts`), no en la carpeta de la app.
La bóveda de contraseñas vive en `%LOCALAPPDATA%\EmiToolkit` de quien la usa.

### Sin interfaz

Los módulos de `Modules\` funcionan sueltos desde PowerShell, por si algún día
hace falta automatizar sin abrir la ventana:

```powershell
Import-Module "$env:ProgramFiles\EmiToolkit\Modules\EmiCore.psm1", "$env:ProgramFiles\EmiToolkit\Modules\EmiFirewall.psm1"
Initialize-EmiCore -RootPath "$env:ProgramFiles\EmiToolkit"
Invoke-EmiEsetFirewall -ResolveHostnames
```

---

## Estructura

```
EmiToolkit\
  EmiToolkit.cmd          lanzador (pide administrador)
  EmiToolkit.ps1          arranque, interfaz y cableado de botones
  UI\MainWindow.xaml      diseño Frutiger Aero
  Modules\
    EmiCore.psm1          log, diario reversible, helpers, acrylic
    EmiDisk.psm1          discos, análisis y limpieza
    EmiTweaks.psm1        optimización de Windows 11
    EmiPrivacy.psm1       telemetría
    EmiPrivRecs.psm1      recomendaciones de privacidad
    EmiVault.psm1         almacén de contraseñas
    EmiDebloat.psm1       apps preinstaladas y características de Windows
    EmiApps.psm1          aplicaciones instaladas
    EmiVortex.psm1        Vortex y Skyrim
    EmiFirewall.psm1      reglas ESET KB332
    EmiStartup.psm1       programas de arranque
    EmiProcess.psm1       procesos y RAM
    EmiSystem.psm1        Zen, inicio rápido, AnyDesk
    EmiHealth.psm1        informe de salud (solo lectura)
  (datos)                 %ProgramData%\EmiToolkit: logs, diario, copia de hosts,
                          informes de salud (informes\)
                          %LOCALAPPDATA%\EmiToolkit: bóveda de contraseñas
```

## Rendimiento y accesibilidad

- Al arrancar compila como mucho un bloque de C#; la copia compilada se guarda en
  `%ProgramData%\EmiToolkit\cache` (solo administradores) con el hash del código
  en el nombre, y solo se carga si el hash coincide y la carpeta sigue protegida.
  El tiempo de arranque queda anotado en el historial.
- Las consultas del estado del equipo y las listas largas se hacen en segundo
  plano; todas las tareas comparten un único runspace.
- La ventana se ajusta al área de trabajo (pensado para 125-150 % en 1366x768 y
  1080p), las columnas se reparten el ancho y cada fila muestra su texto completo
  al pasar el ratón.
- Contraste de los botones de 5:1 o más, anillo de foco visible, nombres para
  Narrador, teclas de acceso (Alt+letra) y colores del sistema con el contraste
  alto de Windows.

## Requisitos

Windows 11 (probado en build 26200) o Windows 10 1809+, PowerShell 5.1 y
.NET Framework 4.8 — los tres vienen de serie. No necesita nada más.

La transparencia acrylic requiere Windows 11 22H2 o superior; en versiones
anteriores la ventana simplemente se ve opaca, todo lo demás funciona igual.

---

Fuente de los datos de red de ESET: artículo **KB332**, revisión del 24-jul-2026.
