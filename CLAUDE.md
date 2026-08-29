# CLAUDE.md — SFPoint

> Para agentes IA. SFPoint tiene **DOS superficies**: el laser (`⌥P`) y la
> pizarra (`⌥L`). Herramientas hay tres —lapiz, marcador, goma— y se eligen con
> UNA tecla o desde la paleta.
>
> ⚠️ **Lo prohibido sigue prohibido, pero la paleta NO es lo prohibido.** Nada de
> ventanas de preferencias, ajustes ni pestañas: eso se borro en la v2 porque
> nadie lo uso y cada una era superficie que podia romperse. La paleta del lapiz
> es otra cosa —dice que instrumento tienes en la mano AHORA— y existe porque sin
> ella los atajos de una letra son fe ciega: Daniel entro al modo el 29 ago y no
> supo si estaba en lapiz o goma, ni de que color, ni de que calibre. Es ESPEJO
> ademas de cabina: todo se sigue pudiendo hacer con el teclado.

## Que es SFPoint

Una app de barra de menu de macOS con dos cosas encima de todo lo demas:

| | atajo | que hace |
|---|---|---|
| **Laser** | `⌥P` | cicla `apagado → ambar → morado → apagado`. Overlay click-through. |
| **Pizarra** | `⌥L` | dibuja con presion e inclinacion de la tableta **sobre cualquier app**. `⌥⇧L` congela la tinta. |

`Esc` apaga lo que este encendido.

**Los dos modos son EXCLUYENTES**, y no por comodidad: el laser oculta el cursor
y deja pasar el clic; la pizarra lo captura. Encender uno apaga el otro, y ese
cruce vive SOLO en `AppDelegate` —el unico sitio que conoce a los dos— para que
ninguno de los dos controladores tenga que saber del otro.

- El overlay del laser es **siempre click-through** (`ignoresMouseEvents = true`),
  jamas roba el foco (`.nonactivatingPanel`), una ventana por pantalla.
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

## La estela: contorno, no segmentos (26 ago 2026)

**El motor de la estela YA NO es el traducido de Qt.** Los dos motores viejos
pintaban la estela trazando **un segmento por frame** con `setLineWidth` propio,
y eso deja JUNTAS con alpha parcial:

| motor | como se ve | luma media (escena `normal`) |
|---|---|---|
| `segmentos-butt` (el original de Qt) | **escalera** de peldaños en toda la estela | 0.00761 |
| `segmentos-round` (default de v3, ago 21-25) | **collar de cuentas**: los topes se solapan y el alpha se compone dos veces | 0.01015 (**+33%**) |
| **`contorno`** (default desde el 26 ago) | una cinta continua que adelgaza hacia la cola | 0.00716 |

`TrailContour.swift` construye el CONTORNO de la estela (una curva cerrada, el
centro remuestreado con Catmull-Rom y desplazado ±ancho/2 sobre su normal),
recorta a el y pinta el desvanecido con **un solo gradiente**. Un relleno por
capa ⇒ cero juntas. Misma leccion que el motor de tinta de sfmap: *un trazo de
ancho variable es un poligono, no una pila de lineas.*

Coste medido: 0.66–1.47 ms/frame contra 0.53–0.72 del trazo por segmento. A
60 fps y solo mientras el laser esta encendido, cabe de sobra en el frame.

Volver a un motor viejo para comparar: `SFPOINT_TRAIL_STYLE=butt` o `=round`
(el nombre viejo `SFPOINT_TRAIL_CAP` sigue funcionando).

⚠️ **Como se colo el defecto de las cuentas:** el `--selftest` que verifico el
93% contra Qt usa UNA escena con las muestras a 6 px — la separacion mas
pequeña, justo donde el solape de los topes queda tapado por el ancho de la
linea. El artefacto vive a 12–30 px por frame, que es como se mueve un cursor
de verdad. Una escena no es un banco: por eso ahora existe `--banco`.

## El modo lapiz (v4, 29 ago 2026) — la pizarra sobre cualquier app

**El motor de tinta NO se escribio aqui: se PORTO de sfmap**
(`~/Developer/software/sfmap/Sources/SFMap/Tinta.swift`), donde esta calibrado
contra **32 trazos reales de la Huion Kamvas 13 de Daniel** y verificado con un
banco de 42 casos y tres rondas de critico ciego. `Tinta.swift` de este repo es
una copia con **una sola diferencia**: la escalera de grosores entra por
parametro en vez de venir de la barra de herramientas de sfmap.

**Verificado, no supuesto:** los dos motores se compilaron por separado contra el
mismo banco y se comparo la GEOMETRIA que producen —22,622 elementos de camino,
16 casos— y salio **identica digito a digito**. Si el motor mejora en sfmap, se
vuelve a portar; aqui no se le mete mano a ojo.

### Como se usa

| tecla | |
|---|---|
| `⌥L` | entrar / salir (al salir se limpia la tinta) |
| `⌥⇧L` | **congelar**: la tinta se queda y el clic vuelve a las apps de abajo |
| `Esc` | salir y limpiar |
| `P` o `L` · `M` · `E` | lapiz · marcador (translucido) · goma |
| `1..5` | morado · ambar · blanco · negro · rojo |
| clic en el disco de la paleta | abre la ESCALERA entera (9 lapiz · 6 marcador · 5 goma) |
| `[` `]` · `,` `.` · rueda · dial | grosor, un peldaño (los cuatro mapeos del driver de Huion) |
| **`⌃P` · `⌃M` · `⌃E`** | lapiz · marcador · goma — **los botones del lapiz fisico**, iguales a sfmap |
| `⌘Z` / `⇧⌘Z` | deshacer / rehacer (los dos también en la paleta) |
| `C` o `⌫` | limpiar |
| `H` | esconder/mostrar la paleta (para grabar sin ella en cuadro) |
| boton derecho | borra sin cambiar de herramienta |
| **voltear la pluma** | la punta de goma de la Kamvas borra sola (`tabletProximity`) |

### Decisiones que NO se cambian sin leer esto

1. **UNA SOLA PANTALLA, la del cursor al entrar** (firmado por Daniel el 29 ago:
   *"si funciona en una pantalla, solo sea en una, no en las 2; el foco no
   tenderá a ser en ambas"*). Capturar el raton en los dos monitores convierte el
   segundo —donde vive el guion, el chat o el codigo que vas a anotar— en una
   superficie muerta. Para mudarla: salir, pasar el cursor, volver a entrar.
   La tinta igual vive en coordenadas GLOBALES de escritorio, como el laser: es
   lo que deja que la ventana se mude de monitor sin tocar el modelo.
2. **El contorno se cachea en el `Trazo`**, no en un mapa con claves. sfmap si
   tiene una `CacheTinta` porque sus trazos se mueven dentro de un documento;
   aqui un trazo se dibuja, se borra entero o se limpia la pizarra. Portar esa
   cache habria sido traerse la MATERIA de sfmap en vez del OFICIO.
3. **La goma es de TRAZO, no de pixel**, y el disco que se pinta ES el radio que
   borra (regla de sfmap). Una goma que promete un area y actua en otra obliga a
   apuntar en vez de a pasar.
4. **`NSEvent.isMouseCoalescingEnabled = false` mientras dura el trazo**, y se
   restaura en `soltarGesto()`, por donde pasan TODAS las salidas —incluido
   salirse con Esc a media linea—. En sfmap, por esa puerta, la fusion se quedaba
   apagada el resto de la vida del proceso.
5. **`isFloatingPanel = true` REESCRIBE el nivel de ventana a `.floating`.** El
   `level` se asigna DESPUES o la pizarra queda empatada con el laser. No se ve a
   ojo: lo caza `--pizarra-humo`.
6. **El area de seguimiento se instala en `viewDidMoveToWindow`**, no en
   `updateTrackingAreas`: AppKit solo llama a esa cuando hay que redibujar, y una
   pizarra vacia no se redibuja nunca — el disco de la goma no seguia al cursor
   hasta el primer trazo.
7. **El rasterizador es UNO SOLO** (`PintorTinta.pintar`): la pantalla y el banco
   de verificacion pintan con la misma funcion, o el banco mediria su propio
   dibujante en vez del motor.
8. **La paleta vive en su PROPIO panel**, por encima del lienzo. Eso es lo que
   hace que pulsar un boton no deje un garabato: el clic entra por una ventana
   distinta y nunca toca la vista que dibuja. Su geometria vive en UNA lista de
   zonas que leen el pintado y el clic — dos listas era el defecto clasico de una
   barra hecha a mano. Se arrastra por el asa y recuerda donde la dejaste.
9. **El HUD calla cuando la paleta esta a la vista.** Con las dos, el mismo dato
   aparecia dos veces y el acuse pasaba a ruido. Solo habla si escondes la paleta.
10. **Cada boton de la paleta lleva su ROTULO nativo con el atajo.** Nacio de
   Daniel preguntando *"¿que hace el copo de nieve?"*: un icono que hay que
   preguntar no comunica, y ninguno tiene hueco para una palabra. El rotulo dice
   el nombre Y la tecla, que es como se aprende a dejar de usar la barra.
11. **LOS COMANDOS DE TABLETA SON LOS DE SFMAP, no unos parecidos.** `⌃P/⌃M/⌃E`
   (los botones del lapiz fisico de la Kamvas, con CONTROL porque una tableta
   manda su combinacion sin que haya un dedo cerca del teclado) y las cuatro
   teclas del dial (`[ ] , .`). El mismo lapiz tiene que hacer lo mismo en las
   dos apps o el musculo se parte en dos. Y la rueda se lee por el EJE MAYOR,
   no por `deltaY`: las dos ruedas de la Kamvas son indistinguibles por
   procedencia y lo unico que las separa es el eje — leyendo solo la vertical,
   la de abajo no hacia nada. `SFPOINT_SONDA_DIAL=1` se lo pregunta al aparato.
   `Pizarra.esDialDeTableta` esta portado de sfmap por si algun dia hay que
   distinguirlos de verdad (pid 0 = raton real; el dial llega del driver).
12. **El grosor es UN boton que abre la escalera**, no un `−/+`. Contar ocho
   pulsaciones para ir de 1 a 9 sin ver a donde vas no es elegir; la tira
   ademas ENSEÑA cuantos peldaños hay. Cada instrumento trae su escalera y su
   MARCA (disco lleno · banda translucida · aro), con rampa de RAIZ porque en
   lineal los cuatro primeros peldaños del lapiz son la misma mota.
13. **La muestra de calibre es un DISCO del diametro real**, no un numero: la
   misma verdad que el disco de la goma en el lienzo. Y el marcador se pinta
   sobre un chip claro, porque su translucidez sobre el grafito de la barra se
   veia marron y mentia sobre el color que pinta.

### El presupuesto del fotograma (medido, no prometido)

| | media | p95 |
|---|---|---|
| repintado COMPLETO de 48 trazos a 4K (peor caso absoluto) | 3.01 ms | 3.69 ms |
| trazo VIVO de 160 muestras: motor + relleno | 0.08 ms | 0.12 ms |

Presupuesto a 120 Hz: 8.3 ms. Y la pantalla real solo repinta el rectangulo
sucio de la COLA del trazo, no la pizarra entera.

## Comandos

```bash
bash scripts/build-app.sh              # compila + firma → dist/SFPoint.app
bash scripts/install.sh                # build + instala en /Applications + lanza
swift build -c release                 # solo compilar

# verificacion sin abrir la app
./.build/release/SFPoint --selftest /tmp/out.png --color ambar
./.build/release/SFPoint --pizarra-test          # modelo: goma, deshacer, escaleras
./.build/release/SFPoint --pizarra-humo          # cableado REAL de AppKit, sin pintar nada
./.build/release/SFPoint --banco-tinta /tmp/bt   # los 16 casos del banco de sfmap a PNG + tiempos
./.build/release/SFPoint --permiso               # TCC: concedido o no
./.build/release/SFPoint --tap-test              # que clase de tap dejo crear macOS
./.build/release/SFPoint --paleta-png /tmp/p.png # la paleta en 3 estados, a PNG
./.build/release/SFPoint --banco /tmp/banco --color ambar   # 3 motores x 3 velocidades + hoja.png
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
3. **El tap deja pasar TODO menos ⌥L y ⌥⇧L.** ⌥P, Esc y lo demas se reenvian
   intactos a la app de enfrente. La excepcion tiene una razon medible: ⌥L
   ESCRIBE `¬`, y abrir la pizarra encima de un editor le metia un caracter
   basura al texto cada vez. Ademas el tap se crea en DOS intentos —consumir
   teclas pide Accesibilidad, escucharlas pide Monitorizacion de entrada, son
   permisos DISTINTOS— y si el primero falla se cae al de solo escucha en vez de
   quedarse sordo: degradar, no morir.
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
  TrailContour.swift    la estela como contorno relleno (el motor vivo)
  SelfTest.swift        render headless a PNG + banco de la estela (--banco)
  Tinta.swift           EL MOTOR DE TINTA, portado de sfmap (no editar a ojo)
  Pizarra.swift         modelo: trazo, instrumentos, historia, regla de la goma
  PizarraOverlay.swift  panel/vista por pantalla: captura de pluma y pintado
  PizarraController.swift  modo, teclas, goma, HUD
  PizarraPaleta.swift   la paleta: su propio panel, arrastrable, espejo del estado
  PizarraTira.swift     la escalera de grosores + el Animador (valor que persigue)
  PizarraTest.swift     --pizarra-test · --pizarra-humo · --banco-tinta
  main.swift            entry point
```

La version Python vive en la rama `main` como historico. `CLAUDE-python-v2.md.bak`
guarda su documentacion.
