# Emi Toolkit

Aplicación de mantenimiento para Windows 11. Interfaz WPF con la transparencia
nativa del sistema (acrylic), estilo Frutiger Aero. Sin terminal, sin instalación,
sin compilar nada: es una carpeta portable.

---

## Cómo se usa

Doble clic en **`EmiToolkit.cmd`** y aceptar el aviso de administrador.

La app arranca en **modo básico**: solo dos apartados, *Inicio* y *Asistencia (AnyDesk)*.
El botón **Optimizar ahora** hace todo el mantenimiento solo.

El interruptor **Modo avanzado** (abajo a la izquierda) despliega los ocho
apartados restantes para ajustar cada cosa por separado.

---

## Qué hace el botón "Optimizar ahora"

En este orden, y anotando cada cambio para poder deshacerlo:

1. Punto de restauración del sistema (opcional, marcado por defecto)
2. **Limpieza de disco** — temporales, caché de Windows Update, Delivery
   Optimization, volcados, informes de error, miniaturas, papelera, logs,
   restos de instalación y cachés de navegadores
3. **Optimización de Windows 11** — quita Widgets, Copilot, el icono de Chat,
   la búsqueda web de Bing, sugerencias y anuncios, la sección Recomendado,
   Xbox Game Bar, apps en segundo plano; pone el menú contextual clásico,
   desactiva 20 servicios innecesarios y las tareas programadas de rastreo
4. **Telemetría** — nivel 0 por directiva, DiagTrack detenido, ID de publicidad,
   experiencias personalizadas, historial de actividad, voz y escritura,
   diagnóstico entre apps, informes de error, telemetría de Edge, búsqueda en
   la nube y Delivery Optimization limitado a la LAN
5. **Arranque** — desactiva los programas de arranque conocidos como innecesarios
6. **Inicio rápido** — lo desactiva si estaba activo
7. **Firewall de ESET** — aplica las reglas del KB332 (opcional)
8. **Zen Browser** — lo pone como predeterminado si está instalado (opcional)

Al terminar muestra cuánto espacio se liberó y recomienda reiniciar.

---

## Los apartados del modo avanzado

| Apartado | Para qué sirve |
|---|---|
| **Espacio en disco** | Estado de cada disco, análisis de basura con el tamaño de cada ubicación, limpieza selectiva, DISM, y un buscador de archivos y carpetas pesados (los borrados van a la papelera) |
| **Optimizar Windows** | Las 19 optimizaciones una por una, con las recomendadas premarcadas |
| **Telemetría** | Los 17 ajustes de privacidad por separado, incluido el bloqueo de dominios en el archivo `hosts` |
| **Firewall ESET** | Los 28 grupos del KB332, prueba de conexión contra los servidores de ESET, y quitar las reglas |
| **Arranque** | Todo lo que arranca con Windows (registro, carpetas de Inicio y tareas programadas) con su estado real, y se desactiva o reactiva |
| **Procesos y RAM** | Procesos agrupados por consumo, clasificados en Sistema / Telemetría / Prescindible / Normal; se pueden cerrar y dejar sin acceso a Internet |
| **Navegador y energía** | Zen como predeterminado, inicio rápido e hibernación |
| **Registro y deshacer** | Log en vivo y el botón que revierte **todos** los cambios |

---

## Lo que NO toca

- **Transparencia y animaciones de Windows** — pedido explícitamente, quedan intactas
- **Windows Defender**, Windows Update y la activación de Windows
- **ESET** — `ekrn`, `egui`, `ESET VPN` y cualquier proceso o entrada de arranque
  que contenga "eset" están en la lista protegida y nunca se desactivan
- Audio (Realtek, Nahimic, Dolby), touchpad (Synaptics, ELAN), utilidades del
  fabricante y procesos críticos del sistema — también protegidos
- **Zen**: si no está instalado, no se cambia nada de navegadores

---

## Deshacer

Cada cambio del registro, servicio, tarea programada, entrada de arranque y regla
de firewall se guarda en `Data\undo-journal.json` con su valor anterior.

**Registro y deshacer → Revertir todos los cambios** lo devuelve todo a su estado
original, en orden inverso. Además queda el punto de restauración del sistema.

Los archivos borrados desde el buscador van a la **papelera**, no se eliminan.

---

## Despliegue en varios equipos

La carpeta es portable y no escribe nada fuera de sí misma salvo los cambios del
sistema que aplica.

```
robocopy "\\servidor\compartido\EmiToolkit" "C:\EmiToolkit" /E
```

Luego se ejecuta `C:\EmiToolkit\EmiToolkit.cmd` en cada equipo.

Cada máquina genera su propio `Data\EmiToolkit_AAAAMMDD.log` y su propio
`undo-journal.json`, así que conviene **copiar la carpeta limpia** a cada equipo
(sin la carpeta `Data` de otro) para que el "deshacer" corresponda a esa máquina.

### Sin interfaz

Los módulos de `Modules\` funcionan sueltos desde PowerShell, por si algún día
hace falta automatizar sin abrir la ventana:

```powershell
Import-Module C:\EmiToolkit\Modules\EmiCore.psm1, C:\EmiToolkit\Modules\EmiFirewall.psm1
Initialize-EmiCore -RootPath C:\EmiToolkit
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
    EmiFirewall.psm1      reglas ESET KB332
    EmiStartup.psm1       programas de arranque
    EmiProcess.psm1       procesos y RAM
    EmiSystem.psm1        Zen, inicio rápido, AnyDesk
  Data\                   logs y diario de deshacer (se crea sola)
```

## Requisitos

Windows 11 (probado en build 26200) o Windows 10 1809+, PowerShell 5.1 y
.NET Framework 4.8 — los tres vienen de serie. No necesita nada más.

La transparencia acrylic requiere Windows 11 22H2 o superior; en versiones
anteriores la ventana simplemente se ve opaca, todo lo demás funciona igual.

---

Fuente de los datos de red de ESET: artículo **KB332**, revisión del 24-jul-2026.
