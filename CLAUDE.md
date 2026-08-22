# CLAUDE.md — SFPoint

> Para agentes IA. SFPoint v3 es un **puntero laser y nada mas**.
> Si estas a punto de agregar una herramienta, una barra o un panel de ajustes:
> no lo hagas. Todo eso se borro a proposito (v1 los tenia, nadie los uso, y
> cada uno era superficie que podia romperse).

## Que es SFPoint

Una app de barra de menu de macOS que dibuja un punto laser de neon sobre todo.
`⌥P` cicla `apagado → ambar → morado → apagado`. `Esc` lo apaga.
Esa es toda la superficie del producto.

- El overlay es **siempre click-through** (`ignoresMouseEvents = true`), jamas roba
  el foco (`.nonactivatingPanel`), una ventana por pantalla.
- Colores: ambar `#F59E0B`, morado `#8C27F1`. El ripple del clic es siempre el
  color contrario al laser activo.

## v3 — Swift nativo (ago 2026)

**La app era Python + PyQt6 + pynput. Ahora es Swift puro.** Misma app, mismo
aspecto, sin runtime interpretado.

| | v2 (Python) | v3 (Swift) |
|---|---|---|
| Peso | ~50 MB con PyQt | **244 KB** (1.4 MB con icono) |
| Dependencias | venv + 4 paquetes | **ninguna** |
| Overlay | QWidget + puente objc | `NSPanel` nativo |
| Atajo | pynput | `CGEventTap` propio |
| Dibujo | QPainter | Core Graphics |

**El render se tradujo 1:1**, no se re-diseño: mismas 9 paradas del gradiente
radial, mismas 3 pasadas de estela, mismas 4 capas del ripple, mismas constantes.
Verificado contra el motor Python pixel a pixel: **93% de pixeles identicos,
diferencia media 0.12/255, cero pixeles con delta perceptible**.

Lo unico que cambio a proposito: el **tope de la estela** pasó de plano
(`.butt`, que dejaba escalones visibles entre segmentos) a redondeado
(`.round`). Volver al original: `SFPOINT_TRAIL_CAP=butt`.

## Comandos

```bash
bash scripts/build-app.sh              # compila + firma → dist/SFPoint.app
bash scripts/install.sh                # build + instala en /Applications + lanza
swift build -c release                 # solo compilar

# verificacion sin abrir la app
./.build/release/SFPoint --selftest /tmp/out.png --color ambar
./.build/release/SFPoint --demo 10 --color morado   # enciende el laser 10s
```

## Invariantes que NO se pueden romper

1. **Firma `SFlow Dev`, jamas ad-hoc.** Ad-hoc cambia el cdhash en cada rebuild
   y macOS revoca Monitorizacion de entrada — que es EXACTAMENTE el permiso del
   que depende ⌥P. Una app firmada ad-hoc se ve viva y queda sorda sin avisar.
   El gate de `build-app.sh` aborta si el cert no existe.
2. **El cursor se oculta y se restaura BALANCEADO.** `LaserController` cuenta
   cada `CGDisplayHideCursor` y los deshace todos al apagar. Un contador
   desbalanceado deja al usuario sin cursor en TODO el sistema, sin recuperacion
   salvo reiniciar. `shutdown()` se llama siempre antes de salir.
3. **El tap es `.listenOnly`.** Nunca se traga la tecla: ⌥P sigue llegando a la
   app que este al frente.
4. **El tap se revive solo.** Si macOS lo deshabilita por timeout, `handle()` lo
   vuelve a habilitar — un tap apagado se ve identico a uno vivo.
5. **Solo se repinta el rectangulo sucio.** Apagado: cero timers, cero
   listeners, ~0% CPU. Encendido: un timer a 60fps sobre la region sucia.

## Estructura

```
Sources/SFPoint/
  Config.swift          constantes (colores, geometria, estados)
  LaserRenderer.swift   dibujo puro: estela + punto + ripple
  LaserOverlay.swift    NSPanel + NSView por pantalla
  LaserController.swift estado, trail, ripples, timer, cursor
  Hotkey.swift          CGEventTap + permisos TCC
  AppDelegate.swift     barra de menu, ciclo de vida, watchdog de permisos
  SelfTest.swift        render headless a PNG con metricas
  main.swift            entry point
```

La version Python vive en la rama `main` como historico. `CLAUDE-python-v2.md.bak`
guarda su documentacion.
