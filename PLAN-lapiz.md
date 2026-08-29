# SFPoint v4 — MODO LÁPIZ (dibujar sobre CUALQUIER app)

> **ESTADO:** TERMINADO
> **ULTIMO_LATIDO:** 2026-08-29T05:56:37
> **Encargo de Daniel (28 ago, noche):** *"en sfmap hay cierta función para usar un lápiz con
> una tableta digital para tomar la presión y todo el pedo. quiero lograr lo mismo con sfpoint,
> como un lápiz y goma aparte, con la capacidad de dibujar no solo sobre el lienzo sino sobre
> CUALQUIER app, con el comando ⌥L. Asegúrate que todo esto quede super smooth."*

Si eres un agente que retoma esto en frío: lee este archivo entero, mira el checklist de abajo,
y **sigue hasta que ESTADO diga TERMINADO**. Repo: `~/Developer/software/sfpoint` (rama `swift`).

---

## Qué se está construyendo

SFPoint hoy es un puntero láser (⌥P). Se le agrega una **segunda superficie**: una PIZARRA
transparente sobre toda la pantalla, con el motor de tinta de sfmap (presión + inclinación de la
Huion Kamvas 13), lápiz y goma como herramientas separadas, encendida/apagada con **⌥L**.

**El motor NO se reescribe: se porta.** `~/Developer/software/sfmap/Sources/SFMap/Tinta.swift`
(904 líneas) es una función pura de CoreGraphics — puntos → `CGPath` de contorno relleno. Su
única dependencia externa es `RailHerramientas.grosores`, que se sustituye por una lista local.
La goma se porta de `sfmap/Sources/SFMap/Goma.swift` (regla pura: el disco que se pinta ES el
disco que borra).

## Decisiones de diseño (firmadas al arrancar)

1. **Láser y lápiz son EXCLUYENTES.** Entrar a lápiz apaga el láser (uno oculta el cursor y es
   click-through; el otro captura el ratón). Documentado, no accidental.
2. **⌥L entra y sale.** Al salir, la tinta se BORRA. `⌥⇧L` = *congelar*: la tinta se queda
   visible y el overlay vuelve a ser click-through (anotación fija sobre la pantalla).
   `Esc` sale del modo lápiz (antes que apagar el láser).
3. **El panel se vuelve `key` mientras dibuja** (`.nonactivatingPanel` + `canBecomeKey`), así
   hay teclas de una letra sin tocar el tap global — que sigue siendo `.listenOnly` (invariante 3
   de la app). El tap global solo aprende ⌥L / ⌥⇧L.
4. **Trazos en coordenadas GLOBALES**, como el láser: un trazo que cruza monitores se pinta en
   los dos. Cada panel traslada por `screenOrigin`.
5. **Caché de mapa de bits por pantalla:** los trazos terminados se componen UNA vez en un
   bitmap (a `backingScaleFactor`); en cada frame solo se recalcula el trazo VIVO. Sin esto, una
   pizarra con 40 trazos pagaría el spline entero 120 veces por segundo.
6. **La goma es de TRAZO** (se lleva el trazo que toca), no de píxel: es lo que permite tener el
   bitmap y es la semántica de sfmap. El disco que se pinta es el radio que borra.
7. **La punta de goma de la pluma** (`NSEvent.pointingDeviceType == .eraser`) cambia a goma sola
   mientras esté volteada. Voltear la pluma es la goma; no hay que buscar una tecla.
8. **Sin panel de ajustes** (`CLAUDE.md` de sfpoint lo prohíbe). Solo un HUD efímero que se
   desvanece a los ~1.4 s cuando cambias herramienta/color/grosor, y las entradas nuevas del
   menú de barra (segunda superficie obligatoria por la lección TCC).
9. **`NSEvent.isMouseCoalescingEnabled = false` mientras dura el trazo**, restaurado en el
   `didSet` del gesto (no en `mouseUp`): salir por Esc a media línea no puede dejarlo apagado.

## Teclas dentro del modo lápiz

| tecla | qué hace |
|---|---|
| `⌥L` | entrar / salir (fuera y dentro del modo) |
| `⌥⇧L` | congelar: deja la tinta y devuelve el clic a las apps |
| `Esc` | salir y limpiar |
| `P` / `L` | lápiz · `E` goma · `M` marcador (translúcido) |
| `1..5` | morado · ámbar · blanco · negro · rojo |
| `[` `]` | grosor abajo/arriba (misma escalera que sfmap) · rueda o dial de la tableta también |
| `⌘Z` / `⇧⌘Z` | deshacer / rehacer |
| `C` o `⌫` | limpiar la pizarra |

## Checklist

- [x] Leer el motor de tinta de sfmap E2E + la goma + la captura de pluma (`puntoDePluma`)
- [x] Leer sfpoint E2E (Config, Hotkey, LaserController, LaserOverlay, AppDelegate)
- [x] `Tinta.swift` portado a sfpoint (sin dependencias de sfmap)
- [x] `Pizarra.swift` — modelo: trazo, herramientas, colores, deshacer, goma
- [x] `PizarraOverlay.swift` — panel/vista por pantalla, captura de pluma, bitmap
- [x] `PizarraController.swift` — modo, teclas, cursor, HUD
- [x] `Hotkey.swift` — ⌥L / ⌥⇧L en el tap
- [x] `AppDelegate` — entradas de menú + exclusión con el láser
- [x] `--banco-tinta` : verificación headless a PNG (sin abrir la app, sin robar foco)
- [x] Medición de latencia por fotograma (presupuesto: 8.3 ms a 120 Hz)
- [x] `build-app.sh` firmado con `SFlow Dev` + instalado en /Applications
- [x] CLAUDE.md y README de sfpoint actualizados
- [x] Commit + push

## Reglas que NO se pueden romper (heredadas)

- Firma **`SFlow Dev`**, jamás ad-hoc (ad-hoc mata Monitorización de entrada en cada rebuild).
- El cursor se oculta/restaura **balanceado** (`cursorHides`).
- El tap es `.listenOnly`; nunca se traga una tecla.
- Solo se repinta el rectángulo sucio.
- **Nada emerge en deep work**: la verificación es headless (PNG), no abriendo ventanas encima
  de Daniel.

---

## CERRADO — 29 ago 2026, 06:0x

**Lo que quedó** (verificado, no prometido):

| verificación | resultado |
|---|---|
| geometría del motor portado vs. el de sfmap (16 casos, 22,622 elementos) | **idéntica dígito a dígito** |
| `--pizarra-test` (modelo: goma, deshacer, escaleras, marcador, toque) | 15/15 en verde |
| `--pizarra-humo` (cableado REAL de AppKit, 2 pantallas, sin pintar nada) | 21/21 en verde |
| repintado completo de 48 trazos a 4K (peor caso) | 3.01 ms media · 3.69 p95 (de 8.3 de presupuesto) |
| trazo vivo de 160 muestras (motor + relleno) | 0.08 ms media · 0.12 p95 |
| firma + TCC | requisito designado IDÉNTICO antes y después · Monitorización CONCEDIDA |
| tap | crea `.defaultTap` → ⌥L NO escribe `¬` |

**Dos fallos que solo cazó la prueba de humo** (invisibles a ojo, ambos arreglados):
`isFloatingPanel = true` reescribe el nivel de ventana, y el área de seguimiento
no existía hasta el primer redibujado (una pizarra vacía no se redibuja nunca).

**El cron nocturno disparó 4 veces y murió las 4** con *"You've hit your weekly
limit · resets Aug 30 at 5pm"*. El candado del latido funcionó (a las 21:03 se
abstuvo con la sesión viva); lo que no había era cuota. El trabajo lo terminó la
sesión al volver. El launchd quedó DESCARGADO: un job que sigue disparando cuando
ya no hay nada que hacer es un órgano zombie. `scripts/nocturno.sh` se queda en el
repo como patrón reutilizable.

**Lo único que no se puede verificar sin la mano encima:** que macOS rutee el clic
FÍSICO al panel (depende de `ignoresMouseEvents` y del nivel), y el SIGNO de la
inclinación con la pluma de verdad — si la caligrafía sale espejada, es un signo
en `PizarraController.punto`.
