//
//  Tinta.swift — EL MOTOR DE TINTA, PORTADO DESDE SFMAP
//
//  ⚠️ ESTE ARCHIVO ES UN PORTE, NO UN ORIGINAL. La fuente viva es
//     ~/Developer/software/sfmap/Sources/SFMap/Tinta.swift (commits `ae6cebb`
//     el motor + `8a6e7c9` la calibración final), donde está calibrado contra
//     32 trazos REALES de la Huion Kamvas 13 de Daniel y verificado con un
//     banco de 42 casos y tres rondas de crítico ciego. Si el motor mejora
//     allá, se vuelve a portar; no se le meta mano aquí a ojo.
//
//  Se puede portar tal cual porque es una FUNCIÓN PURA: puntos de pluma →
//  `CGPath` de contorno. No conoce pantallas, ni documentos, ni AppKit. La
//  única atadura que tenía a sfmap era la escalera de grosores de su barra de
//  herramientas, y aquí entra por parámetro (ver `grosorAjustado`).
//

import CoreGraphics
import Foundation

/**
 * EL MOTOR DE TINTA. Puntos crudos de la pluma → un contorno relleno.
 *
 * ── POR QUÉ NO ERA "ponerle más suavizado" ───────────────────────────────────
 *
 * Lo de antes unía los puntos con `addLine` y cambiaba `setLineWidth` por
 * segmento. Eso tiene DOS fallos que ningún parámetro arregla: la línea entre
 * dos muestras es RECTA (poligonado en cada curva) y cada segmento es un trazo
 * INDEPENDIENTE con su propio ancho (una "cuenta" en cada junta, y en el
 * marcador translúcido cada junta se pinta dos veces y se ve más oscura).
 *
 * Aquí el trazo es UN polígono cerrado que se rellena una vez. No hay juntas
 * porque no hay segmentos.
 *
 * ── LO QUE MIDIÓ EL DIAGNÓSTICO ──────────────────────────────────────────────
 *
 * Sobre los 32 trazos reales de Daniel con la Kamvas 13 (555 puntos):
 *
 *   · La presión NUNCA llega arriba: p50 = 0.294, p90 = 0.478, p99 = 0.635,
 *     máx 0.737. Una respuesta lineal sobre 0..1 usa medio instrumento y deja
 *     el trazo plano. El techo útil se calibra al techo REAL (`TOPE_PRESION`).
 *   · La presión llega CUANTIZADA a 1/256 (0.0039, 0.0078, …). Los 16384
 *     niveles del catálogo no cruzan el driver; el escalón de 1/256 sobre un
 *     ancho de 5 unidades es visible y hay que filtrarlo.
 *   · Las muestras están LEJOS: mediana 5.3 unidades entre puntos, p90 19.4,
 *     máx 41.3. Ése es el defecto dominante — no el temblor. Por eso el
 *     "streamline" del referente (que arrastra cada punto hacia el anterior)
 *     aquí RESTA: sobre datos ya escasos redondea las letras y encoge el trazo.
 *     Lo que hace falta es INTERPOLAR, no promediar.
 *
 * ── LAS CINCO PIEZAS ─────────────────────────────────────────────────────────
 *
 *  1. Estabilización ADAPTATIVA A LA DENSIDAD: el filtro muerde cuando las
 *     muestras están juntas (donde vive el temblor) y se aparta cuando están
 *     lejos (donde borraría la letra). Una sola fórmula, sin suponer ninguna
 *     frecuencia de muestreo — así el mismo código sirve para un ratón a 60 Hz
 *     y para la pluma sin coalescer.
 *  2. Centro por SPLINE de Catmull-Rom CENTRÍPETA (α = 0.5): pasa por todos
 *     los puntos, no inventa lazos ni sobrepasos en las esquinas cerradas
 *     —que es justo lo que hace la uniforme— y da curva de verdad entre
 *     muestras separadas 20 unidades.
 *  3. Ancho continuo = presión filtrada × velocidad × plumilla × entrada/salida.
 *  4. PLUMILLA ELÍPTICA con la inclinación de la PW600L: la punta se alarga
 *     hacia donde se recuesta la pluma, así que cruzar la inclinación pinta
 *     grueso y seguirla pinta fino. Es la caligrafía de plumín ancha de toda
 *     la vida, y es lo que el referente web NO puede hacer: un ratón no tiene
 *     ángulo.
 *  5. Contorno cerrado con esquinas suavizadas (cuadrática por punto medio) y
 *     relleno NON-ZERO: un trazo que se cruza a sí mismo se rellena una vez,
 *     como la tinta de verdad.
 *
 * ── EL MISMO PÍXEL EN VIVO Y GUARDADO ────────────────────────────────────────
 *
 * No hay parámetro `vivo`. El referente tiene uno (`last: !live`) y con él el
 * borrador y el resultado NO son el mismo dibujo. Aquí el modo no existe: el
 * motor es una función pura de los puntos, así que el trazo en curso y el
 * elemento guardado no pueden divergir. La fidelidad no se verifica, se hace
 * imposible. (`TintaTests.borradorYGuardadoSonElMismoCamino` lo prueba.)
 */

/// Un punto de la pluma. `ix/iy` y `t` son ADITIVOS: los trazos viejos no los
/// traen y el motor funciona igual sin ellos.
struct PuntoTinta {
    var x: Double
    var y: Double
    /// Presión cruda 0..1 tal como la entrega el driver.
    var p: Double
    /// Inclinación -1..1 por eje (0,0 = pluma vertical o sin dato).
    var ix: Double = 0
    var iy: Double = 0
    /// Milisegundos desde el inicio del trazo. Negativo = sin dato.
    var t: Double = -1
}

enum Tinta {

    /// Ajuste ergonomico del grosor para la rueda: pasos finos abajo y pasos
    /// enteros cuando el trazo ya es grande. Es puro para que el control de
    /// entrada y su prueba no dependan de AppKit.
    /**
     * EL SIGUIENTE PELDAÑO DE LA ESCALERA, no el siguiente medio pixel.
     *
     * ⚠️ Antes sumaba de 0.5 en 0.5 (1.0 por encima de 8) y con eso el grosor
     * caia entre los valores de la fila del panel: `grosor == g` no se cumplia
     * casi nunca, el panel no marcaba nada y girar la rueda PARECIA no hacer
     * efecto aunque lo hiciera. Daniel: *"al girar el dial yo esperaria ver
     * moverse el grosor"*.
     *
     * Hay UNA escalera y esto anda por ella. El HUD marca el peldaño, el dial
     * lo mueve, y las dos cosas dicen lo mismo porque leen la misma lista. Dos
     * fuentes de "que grosores hay" era el problema, no un detalle de redondeo.
     *
     * En el porte a SFPoint la escalera ENTRA POR PARÁMETRO: aquí hay dos
     * instrumentos con escaleras distintas (el lápiz y la goma) y una constante
     * global volvería a partir la verdad en dos.
     *
     * Si el valor de partida no es un peldaño (viene de un trazo importado o
     * de una version anterior), se entra por el MAS CERCANO en vez de
     * ignorarlo: el primer giro coloca, y a partir de ahi la escalera manda.
     */
    static func grosorAjustado(_ actual: Double, pasos: Int, escalera: [Double]) -> Double {
        guard let cerca = escalera.enumerated()
            .min(by: { abs($0.element - actual) < abs($1.element - actual) })?.offset
        else { return actual }
        guard pasos != 0 else { return escalera[cerca] }
        // Si estabas ENTRE dos peldaños, el primer giro solo te sube al de al
        // lado; no se salta uno por haber empezado descolocado.
        let i = abs(escalera[cerca] - actual) < 0.01
            ? cerca + pasos
            : (pasos > 0 ? (escalera[cerca] > actual ? cerca : cerca + 1)
                         : (escalera[cerca] < actual ? cerca : cerca - 1))
        return escalera[max(0, min(escalera.count - 1, i))]
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la calibración
    // ════════════════════════════════════════════════════════════════════════

    /// El referente web multiplica el grosor elegido por esto para llegar al
    /// diámetro de la plumilla. Se conserva para que el A/B compare CALIDAD y
    /// no peso: dos trazos de grosores distintos no se pueden juzgar.
    static let FACTOR_TAMANO = 1.25

    /// El techo REAL de la Kamvas medido en la tinta de Daniel (p99 = 0.635).
    /// Por encima de esto el ancho ya está al máximo: mapear hasta 1.0 sería
    /// regalar la mitad superior del instrumento a una presión que su mano no
    /// hace nunca.
    static let TOPE_PRESION = 0.62

    /**
     * Rango del ancho como fracción del diámetro.
     *
     * Calibrado MIDIENDO, no a ojo: sobre los 32 trazos reales, el ancho medio
     * (tinta ÷ longitud) sale 3.02 unidades contra las 3.06 del referente —un
     * 1% — y el contraste extremo es 5.5× contra su 3.0×. Es decir: el mismo
     * peso de tinta, repartido con casi el doble de rango. Ése es exactamente
     * el cambio que convierte una línea en una letra, y es la única forma
     * honesta de compararse con otro motor: si uno pinta más grueso, el A/B
     * mide el grosor y no la calidad.
     *
     * El techo bajó de 1.34 a 1.26 por un veredicto ciego: con 1.34 los trazos
     * de presión alta pesaban un 23% más que los del referente y en una "O"
     * pequeña el trazo de entrada se FUNDÍA con el cuerpo, cerrando el ojo de
     * la letra. Más contraste no sirve de nada si se come la contraforma.
     */
    static let ANCHO_MIN = 0.20
    static let ANCHO_MAX = 1.26

    /// Cuánto de curva-en-S lleva la respuesta de presión. La S mete contraste
    /// en el MEDIO del recorrido, que es exactamente donde vive el 80% de las
    /// muestras reales; con 0 el trazo es una rampa y todas las letras pesan
    /// igual.
    static let CURVA_PRESION = 0.55

    /// Velocidad de referencia (unidades de mundo por segundo) y cuánto
    /// adelgaza. Con presión real la velocidad solo matiza; sin presión real
    /// (ratón) es lo ÚNICO que le da vida al trazo.
    static let VEL_REF = 1500.0
    static let VEL_PESO_CON_PRESION = 0.16
    static let VEL_PESO_SIN_PRESION = 0.62
    static let VEL_BASE_SIN_PRESION = 1.12

    /**
     * Entrada y salida. No van a cero —un trazo que acaba en punta de aguja se
     * ve deshilachado— sino a un suelo, y suben con una ese.
     *
     * Y son DOS ajustes, no uno, porque el trabajo que hacen es distinto:
     *
     *  · CON presión real la mano ya entra y sale suave (la tinta de Daniel
     *    empieza en 0.004 y sube). Un afilado largo encima de eso pinta un
     *    DARDO: se midió en `sin-esquina`, siete unidades de cuña donde el
     *    dato decía ancho medio. Aquí el afilado solo redondea la punta.
     *  · SIN presión real (ratón) el trazo entra y sale a plomo, y el afilado
     *    es lo único que lo distingue de una salchicha con dos tapas.
     */
    static let ENTRADA_LARGO_PLUMA = 0.5      // × diámetro
    static let ENTRADA_SUELO_PLUMA = 0.62
    static let ENTRADA_LARGO_RATON = 1.1
    static let ENTRADA_SUELO_RATON = 0.30
    /// Y el MARCADOR no se afila: un rotulador tiene la punta plana y su banda
    /// empieza y acaba a plomo. Afilarlo lo convierte en un pincel.
    static let ENTRADA_LARGO_MARCA = 0.30
    static let ENTRADA_SUELO_MARCA = 0.88

    /// Cuánto se alarga la plumilla con la inclinación máxima (±60°).
    static let PLUMILLA_ALARGUE = 0.85

    /// Umbral de presión real. El mismo que usan los dos referentes: un ratón
    /// (y un dedo) reportan presión constante, y alimentar esa presión "real"
    /// da un trazo muerto.
    static let EPSILON_PRESION = 0.03

    /// Cadencia que se supone cuando el trazo no guarda tiempos. Es la que
    /// mide la tinta vieja: macOS fusiona los eventos de puntero a la cadencia
    /// de pantalla salvo que se le pida lo contrario.
    static let HZ_HEREDADO = 60.0

    /// Tope de muestras por trazo. Un trazo de una página entera no puede
    /// costar un segundo de CPU por su propia longitud.
    static let MAX_MUESTRAS = 6000

    /**
     * EL PULIDO DEL CENTRO, en longitud de arco. (× diámetro)
     *
     * El estabilizador de la captura quita el grueso del temblor, pero deja un
     * residuo, y ese residuo NO se ve como temblor: se ve como CUENTAS en el
     * borde, porque la tangente oscila y con ella la dirección en la que se
     * proyecta el ancho. Un crítico ciego lo cazó en el trazo lento con temblor
     * de ±0.55 unidades: *"bandeado periódico, parece una cuerda con cuentas en
     * vez de un filo continuo"*.
     *
     * Se pule DESPUÉS de la spline y sobre las muestras ya repartidas por
     * longitud de arco, y ahí está la gracia: un filtro de N muestras sobre un
     * muestreo uniforme es un filtro paso-bajo con una longitud de onda
     * definida en UNIDADES DE MUNDO, no en muestras del dispositivo. Sobre
     * entrada escasa la spline ya es lisa y no hay nada que quitar —el filtro
     * es un no-op—; sobre entrada densa y temblorosa, el temblor está justo en
     * la banda que se corta. Se adapta solo, sin suponer ninguna cadencia.
     */
    static let PULIDO = 0.5

    /// Cuánto tiene que saltar la presión para que el filtro se aparte. Por
    /// debajo es ruido de cuantización (la Kamvas entrega escalones de 1/256);
    /// por encima es la mano.
    static let PRESION_SALTO = 0.07

    /// A partir de este giro, el nodo NO es una curva: es una ESQUINA.
    /// La spline pasa por todos los puntos, pero con tangente continua — así
    /// que la punta de una "v" o el vértice de una flecha se le derriten en un
    /// arco. Por encima del umbral el trazo se parte ahí y cada lado llega
    /// recto a su vértice, con una junta redonda del ancho de la plumilla.
    /// 65° deja pasar la letra cursiva entera y caza los vértices de verdad.
    static let ESQUINA_GRADOS = 65.0

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la puerta
    // ════════════════════════════════════════════════════════════════════════

    struct Opciones {
        var grosor: Double = 4
        var marcador: Bool = false
        init(grosor: Double = 4, marcador: Bool = false) {
            self.grosor = grosor
            self.marcador = marcador
        }
    }

    /// El diámetro nominal de la plumilla. El marcador NO lleva el factor: su
    /// grosor ya se elige pensando en el ancho de la banda.
    static func diametro(_ o: Opciones) -> Double {
        let g = max(0.5, o.grosor)
        return o.marcador ? g : g * FACTOR_TAMANO
    }

    /**
     * El contorno del trazo, en las coordenadas de los puntos que se le dan.
     *
     * Devuelve `nil` solo cuando no hay nada que pintar. Un único punto —o
     * varios en el mismo sitio— devuelve un DISCO: soltar la pluma sin mover
     * la mano deja tinta, y el motor viejo dejaba la nada.
     */
    static func camino(_ entrada: [PuntoTinta], _ o: Opciones) -> CGPath? {
        let d = diametro(o)
        let pts = saneados(entrada)
        guard !pts.isEmpty else { return nil }
        if pts.count == 1 { return disco(pts[0], o, d) }

        /*
         * UN TOQUE ES UN PUNTO, NO UNA LÍNEA.
         *
         * `ink-mt55kmkv-24`, en la tinta real: dos muestras separadas 0.098
         * unidades con presión 0.0001. Tratado como trazo sale una mota de
         * décimas de unidad —invisible— porque el afilado de entrada y salida
         * se solapa sobre sí mismo. La pluma bajó y se levantó: eso deja un
         * punto, y su tamaño lo pone la presión MÁS ALTA que llegó a leerse,
         * no la primera.
         */
        var largoTotal = 0.0
        for i in 1..<pts.count { largoTotal += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        if largoTotal < 0.35 * d {
            var c = pts[0]
            c.x = pts.reduce(0) { $0 + $1.x } / Double(pts.count)
            c.y = pts.reduce(0) { $0 + $1.y } / Double(pts.count)
            c.p = pts.reduce(0) { max($0, $1.p) }
            return disco(c, o, d)
        }

        let ns = nodos(pts, o, d)
        if ns.count < 2 { return disco(pts[0], o, d) }

        var ms = muestrear(ns, paso: paso(d))
        if ms.count < 2 { return disco(pts[0], o, d) }
        pulirMuestras(&ms, radio: PULIDO * d, paso: paso(d))
        let real = presionReal(pts)
        let largoEnt = o.marcador ? ENTRADA_LARGO_MARCA : (real ? ENTRADA_LARGO_PLUMA : ENTRADA_LARGO_RATON)
        let sueloEnt = o.marcador ? ENTRADA_SUELO_MARCA : (real ? ENTRADA_SUELO_PLUMA : ENTRADA_SUELO_RATON)
        aplicarEntradaYSalida(&ms, largo: largoEnt * d, suelo: sueloEnt)

        let borde = contorno(ms)
        guard borde.count >= 3 else { return disco(pts[0], o, d) }
        return caminoSuave(borde)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 0 · saneo
    // ════════════════════════════════════════════════════════════════════════

    /// Fuera lo no finito y los duplicados consecutivos. Un duplicado no es
    /// inofensivo: la tangente sale de una resta y dos puntos iguales dan
    /// dirección cero, que es un NaN esperando a nacer.
    private static func saneados(_ e: [PuntoTinta]) -> [PuntoTinta] {
        var out: [PuntoTinta] = []
        out.reserveCapacity(e.count)
        for var q in e {
            guard q.x.isFinite, q.y.isFinite else { continue }
            if !q.p.isFinite { q.p = 0.5 }
            q.p = min(1, max(0, q.p))
            if !q.ix.isFinite { q.ix = 0 }
            if !q.iy.isFinite { q.iy = 0 }
            if let u = out.last, abs(u.x - q.x) < 1e-9, abs(u.y - q.y) < 1e-9 {
                // Mismo sitio: se queda la presión MÁS ALTA. La pluma apoyada
                // quieta sube de presión, y quedarse con la primera muestra
                // convertía un punto firme en una mota.
                if q.p > out[out.count - 1].p { out[out.count - 1].p = q.p }
                continue
            }
            out.append(q)
        }
        return out
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 1 · nodos (estabilizar · presión · velocidad · plumilla)
    // ════════════════════════════════════════════════════════════════════════

    private struct Nodo {
        var c: CGPoint
        /// Semiancho equivalente redondo, antes de la entrada/salida.
        var h: Double
        /// Eje mayor de la plumilla (unitario) y cuánto se alarga.
        var ux: Double, uy: Double, e: Double
    }

    /// ¿Trae presión de verdad? Se mide la VARIANZA, no el tipo de puntero:
    /// un ratón reporta presión constante y creerle produce una línea muerta.
    static func presionReal(_ pts: [PuntoTinta]) -> Bool {
        guard pts.count >= 4 else { return false }
        var mn = Double.infinity, mx = -Double.infinity
        for q in pts { mn = min(mn, q.p); mx = max(mx, q.p) }
        return mx - mn > EPSILON_PRESION
    }

    private static func nodos(_ pts: [PuntoTinta], _ o: Opciones, _ d: Double) -> [Nodo] {
        let real = presionReal(pts)
        // Las tres constantes de tiempo del filtro, en unidades de MUNDO. Que
        // sean distancias y no milisegundos es lo que hace al motor indiferente
        // a la cadencia del dispositivo.
        let lamPos = max(0.35, 0.55 * d)
        let lamPre = max(0.50, 0.90 * d)
        let lamVel = max(0.80, 1.40 * d)

        var out: [Nodo] = []
        out.reserveCapacity(pts.count)

        var sx = pts[0].x, sy = pts[0].y          // posición estabilizada
        var pf = pts[0].p                          // presión filtrada
        var vf = 0.0                               // velocidad filtrada
        var tx = pts[0].ix, ty = pts[0].iy         // inclinación filtrada

        for i in 0..<pts.count {
            let q = pts[i]
            if i > 0 {
                let dx = q.x - sx, dy = q.y - sy
                let dist = (dx * dx + dy * dy).squareRoot()
                // EL FILTRO ADAPTATIVO. `1 - e^(-dist/λ)` vale casi 1 cuando la
                // muestra llegó lejos (se le cree) y casi 0 cuando llegó pegada
                // a la anterior (se la promedia). El temblor vive en las
                // muestras pegadas; la letra, en las separadas.
                let a = 1 - exp(-dist / lamPos)
                sx += dx * a
                sy += dy * a

                let paso = max(1e-6, dist)
                /*
                 * EL FILTRO DE PRESIÓN SE APARTA CUANDO LA MANO HABLA.
                 *
                 * Un promediado plano quita el escalón de 1/256 y, con él, los
                 * ALIVIOS CORTOS de presión: el cruce fino de una "O", el
                 * momento en que la mano suelta al pasar por encima de un
                 * trazo. Un crítico ciego cazó exactamente eso — *"el cruce
                 * inferior se ve relleno y del mismo grosor que el cuerpo"*—
                 * y tenía razón: el ruido y el gesto viven en la misma señal, y
                 * lo que los separa no es la amplitud media, es el SALTO.
                 *
                 * Así que el filtro mide cuánto cambió la presión: si es del
                 * tamaño de un escalón del sensor, promedia; si la mano dio un
                 * respingo, deja pasar. Es la idea del filtro de un euro
                 * aplicada a la presión en vez de a la posición.
                 */
                let salto = min(1, abs(q.p - pf) / PRESION_SALTO)
                let base = 1 - exp(-paso / lamPre)
                pf += (q.p - pf) * (base + (1 - base) * salto * salto)
                tx += (q.ix - tx) * (1 - exp(-paso / lamPre))
                ty += (q.iy - ty) * (1 - exp(-paso / lamPre))

                let dt = intervalo(pts, i)
                let v = paso / max(1e-4, dt)
                vf += (v - vf) * (1 - exp(-paso / lamVel))
            } else {
                pf = q.p
            }

            let u = min(1, max(0, pf / TOPE_PRESION))
            var f: Double
            if o.marcador {
                // El marcador es casi de ancho constante: su gracia es la banda
                // pareja, no la caligrafía.
                f = 0.85 + 0.30 * u
            } else if real {
                f = ANCHO_MIN + (ANCHO_MAX - ANCHO_MIN) * respuesta(u)
            } else {
                // Sin presión real el ancho lo pone la velocidad. El motor
                // viejo pintaba una línea de ancho CONSTANTE aquí: correcto y
                // muerto.
                f = ANCHO_MIN + (ANCHO_MAX - ANCHO_MIN) * 0.5
            }

            let vn = min(1, max(0, vf / VEL_REF))
            if o.marcador {
                f *= 1 - 0.08 * ese(vn)
            } else if real {
                f *= 1 - VEL_PESO_CON_PRESION * ese(vn)
            } else {
                f *= max(0.42, VEL_BASE_SIN_PRESION - VEL_PESO_SIN_PRESION * ese(vn))
            }

            // La plumilla. Sin inclinación (trazo viejo, ratón, pluma vertical)
            // `e` vale 1 y todo esto es un círculo — el caso que hay que no
            // romper.
            var e = 1.0, ux = 1.0, uy = 0.0
            let mag = min(1, (tx * tx + ty * ty).squareRoot())
            if mag > 0.02 && !o.marcador {
                e = 1 + PLUMILLA_ALARGUE * pow(mag, 1.25)
                ux = tx / mag
                uy = ty / mag
            }

            out.append(Nodo(c: CGPoint(x: sx, y: sy), h: max(0.05, 0.5 * d * f),
                            ux: ux, uy: uy, e: e))
        }

        // El ÚLTIMO punto se alcanza exacto. El filtro deja el trazo corto por
        // su propio retardo, y "la tinta no llega a donde llegó la pluma" es de
        // los defectos que la mano nota sin saber nombrarlo.
        if let ult = pts.last, var n = out.last {
            n.c = CGPoint(x: ult.x, y: ult.y)
            out[out.count - 1] = n
        }
        return out
    }

    /// El intervalo real entre dos muestras. Sin tiempos guardados se supone la
    /// cadencia con la que se capturó la tinta vieja — declarado, no adivinado.
    private static func intervalo(_ pts: [PuntoTinta], _ i: Int) -> Double {
        guard i > 0 else { return 1 / HZ_HEREDADO }
        let a = pts[i - 1].t, b = pts[i].t
        guard a >= 0, b >= a else { return 1 / HZ_HEREDADO }
        return max(1e-4, (b - a) / 1000)
    }

    /// La respuesta de presión: rampa mezclada con una ese. La ese mete el
    /// contraste donde están las muestras y aplana los extremos, que es donde
    /// el ruido de 1/256 se vería como nervio.
    static func respuesta(_ u: Double) -> Double {
        let s = u * u * (3 - 2 * u)
        return u * (1 - CURVA_PRESION) + s * CURVA_PRESION
    }

    private static func ese(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 2 · el centro (spline centrípeta) → muestras
    // ════════════════════════════════════════════════════════════════════════

    private struct Muestra {
        var c: CGPoint
        var tx: Double, ty: Double     // tangente unitaria
        var h: Double
        var ux: Double, uy: Double, e: Double
        var s: Double                  // longitud de arco acumulada
    }

    /**
     * El paso del remuestreo, en unidades de mundo.
     *
     * Cuanto más fino, más muestras y más cuesta; y a partir de cierto punto no
     * se gana nada, porque el contorno NO se emite como polilínea sino con
     * cuadráticas de punto medio, que ya interpolan entre muestra y muestra.
     * Medido: bajar de d/5 a d/7 sube el coste un 40% y no cambia un píxel ni
     * con el zoom encima.
     */
    private static func paso(_ d: Double) -> Double {
        min(2.4, max(0.5, d / 5))
    }

    /**
     * Catmull-Rom CENTRÍPETA (α = 0.5) convertida a Bézier cúbica por tramo.
     *
     * La uniforme (α = 0) es la que todo el mundo escribe primero y hace un
     * LAZO cuando dos muestras caen muy juntas junto a una lejana — justo el
     * patrón de una pluma que frena en una curva. La centrípeta tiene
     * demostrado que no se auto-interseca ni sobrepasa, y ése es exactamente
     * el seguro que hace falta con muestras a 20 unidades de distancia.
     */
    /// Los nodos donde el trazo GIRA de golpe. Se calcula sobre el centro ya
    /// estabilizado, no sobre el crudo: si no, el ruido de una muestra suelta
    /// inventaría esquinas que la mano no hizo.
    private static func esquinas(_ n: [Nodo]) -> [Bool] {
        var e = [Bool](repeating: false, count: n.count)
        guard n.count >= 3 else { return e }
        let cosUmbral = cos(ESQUINA_GRADOS * Double.pi / 180)
        for i in 1..<(n.count - 1) {
            let ax = n[i].c.x - n[i - 1].c.x, ay = n[i].c.y - n[i - 1].c.y
            let bx = n[i + 1].c.x - n[i].c.x, by = n[i + 1].c.y - n[i].c.y
            let la = (ax * ax + ay * ay).squareRoot(), lb = (bx * bx + by * by).squareRoot()
            guard la > 1e-6, lb > 1e-6 else { continue }
            // Y con los dos brazos LARGOS: dos muestras pegadas en una curva
            // dan ángulos enormes por redondeo, y partir ahí metería un pico
            // donde el ojo ve una curva.
            let corto = min(la, lb)
            if corto < 0.9 { continue }
            if (ax * bx + ay * by) / (la * lb) < cosUmbral { e[i] = true }
        }
        return e
    }

    private static func muestrear(_ n: [Nodo], paso: Double) -> [Muestra] {
        var out: [Muestra] = []
        out.reserveCapacity(min(MAX_MUESTRAS, n.count * 8 + 8))
        let esq = esquinas(n)

        // Presupuesto: un trazo larguísimo sube el paso en vez de comerse la
        // memoria.
        var largo = 0.0
        for i in 1..<n.count { largo += hypot(n[i].c.x - n[i - 1].c.x, n[i].c.y - n[i - 1].c.y) }
        let pasoReal = max(paso, largo / Double(MAX_MUESTRAS))

        var s = 0.0
        var ultimo: CGPoint? = nil

        for i in 0..<(n.count - 1) {
            let p1 = n[i].c, p2 = n[i + 1].c
            // Una esquina PARTE la spline: el tramo que llega y el que sale
            // dejan de compartir tangente, así que cada uno entra recto a su
            // vértice en vez de rodearlo.
            let p0 = (i > 0 && !esq[i]) ? n[i - 1].c : CGPoint(x: 2 * p1.x - p2.x, y: 2 * p1.y - p2.y)
            let p3 = (i + 2 < n.count && !esq[i + 1]) ? n[i + 2].c
                                                      : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)
            let (b1, b2) = controles(p0, p1, p2, p3)

            // Cuántas muestras: la longitud del polígono de control estima el
            // arco mejor que la cuerda, y en una curva cerrada la diferencia es
            // el doble de puntos justo donde hacen falta.
            let poli = hypot(b1.x - p1.x, b1.y - p1.y) + hypot(b2.x - b1.x, b2.y - b1.y)
                     + hypot(p2.x - b2.x, p2.y - b2.y)
            let k = min(96, max(1, Int(ceil(poli / pasoReal))))

            for j in 0...k {
                // El nodo compartido se emite una vez… salvo que sea esquina:
                // ahí se emite DOS veces, una con la tangente que llega y otra
                // con la que sale, y la junta redonda se dibuja entre ellas.
                if i > 0 && j == 0 && !esq[i] { continue }
                let t = Double(j) / Double(k)
                let c = bezier(p1, b1, b2, p2, t)
                var (dx, dy) = derivada(p1, b1, b2, p2, t)
                var m = (dx * dx + dy * dy).squareRoot()
                if m < 1e-9 {
                    dx = p2.x - p1.x; dy = p2.y - p1.y
                    m = max(1e-9, (dx * dx + dy * dy).squareRoot())
                }
                let vertice = j == 0 && i > 0 && esq[i]
                if let u = ultimo {
                    let paso2 = hypot(c.x - u.x, c.y - u.y)
                    // Muestras casi encimadas producen cuadriláteros
                    // degenerados en el contorno: se descartan salvo la última
                    // del tramo —que hay que conservar para no perder el nodo—
                    // y salvo el vértice de una esquina, que está encimado A
                    // PROPÓSITO porque lo que cambia ahí no es el sitio, es la
                    // dirección.
                    if paso2 < pasoReal * 0.25 && j != k && !vertice { continue }
                    s += paso2
                }
                ultimo = c

                // El ancho se interpola con una ese dentro del tramo: lineal
                // deja un pico de curvatura en cada nodo y el borde del trazo
                // enseña un codo.
                let w = ese(t)
                let a = n[i], b = n[i + 1]
                out.append(Muestra(c: c, tx: dx / m, ty: dy / m,
                                   h: a.h + (b.h - a.h) * w,
                                   ux: a.ux + (b.ux - a.ux) * w,
                                   uy: a.uy + (b.uy - a.uy) * w,
                                   e: a.e + (b.e - a.e) * w,
                                   s: s))
            }
        }
        return out
    }

    /// Los dos controles de la Bézier equivalente a la Catmull-Rom centrípeta.
    private static func controles(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint)
        -> (CGPoint, CGPoint) {
        let a = 0.5
        let d1 = pow(max(1e-9, hypot(p1.x - p0.x, p1.y - p0.y)), a)
        let d2 = pow(max(1e-9, hypot(p2.x - p1.x, p2.y - p1.y)), a)
        let d3 = pow(max(1e-9, hypot(p3.x - p2.x, p3.y - p2.y)), a)

        let n1 = 3 * d1 * (d1 + d2)
        let n2 = 3 * d3 * (d3 + d2)
        let b1 = CGPoint(
            x: (d1 * d1 * p2.x - d2 * d2 * p0.x + (2 * d1 * d1 + 3 * d1 * d2 + d2 * d2) * p1.x) / n1,
            y: (d1 * d1 * p2.y - d2 * d2 * p0.y + (2 * d1 * d1 + 3 * d1 * d2 + d2 * d2) * p1.y) / n1)
        let b2 = CGPoint(
            x: (d3 * d3 * p1.x - d2 * d2 * p3.x + (2 * d3 * d3 + 3 * d3 * d2 + d2 * d2) * p2.x) / n2,
            y: (d3 * d3 * p1.y - d2 * d2 * p3.y + (2 * d3 * d3 + 3 * d3 * d2 + d2 * d2) * p2.y) / n2)
        return (b1, b2)
    }

    private static func bezier(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        return CGPoint(x: a.x * w0 + b.x * w1 + c.x * w2 + d.x * w3,
                       y: a.y * w0 + b.y * w1 + c.y * w2 + d.y * w3)
    }

    private static func derivada(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: Double)
        -> (Double, Double) {
        let u = 1 - t
        let w0 = 3 * u * u, w1 = 6 * u * t, w2 = 3 * t * t
        return ((b.x - a.x) * w0 + (c.x - b.x) * w1 + (d.x - c.x) * w2,
                (b.y - a.y) * w0 + (c.y - b.y) * w1 + (d.y - c.y) * w2)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 2b · el pulido del centro
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Paso-bajo sobre el centro ya remuestreado, y las tangentes recalculadas
     * a partir de él. Ver `PULIDO` para el porqué.
     *
     * Dos cuidados que lo hacen seguro:
     *
     *  · NO CRUZA UNA ESQUINA. En un vértice hay dos muestras en el mismo sitio
     *    con tangentes opuestas; promediarlas derretiría justo lo que la
     *    detección de esquinas acaba de salvar. El arreglo se corta ahí y cada
     *    lado se pule por su cuenta.
     *  · NO MUEVE LOS EXTREMOS. El peso baja a cero en las puntas, o el trazo
     *    encogería por los dos lados cada vez que se pule.
     */
    private static func pulirMuestras(_ ms: inout [Muestra], radio: Double, paso: Double) {
        let k = min(6, Int((radio / max(1e-6, paso)).rounded()))
        guard k >= 1, ms.count >= 2 * k + 3 else { return }

        // Los cortes: donde dos muestras comparten sitio y cambian de rumbo.
        var corte = [Bool](repeating: false, count: ms.count)
        for i in 1..<ms.count {
            let a = ms[i - 1], b = ms[i]
            let giro = abs(atan2(a.tx * b.ty - a.ty * b.tx, a.tx * b.tx + a.ty * b.ty))
            if giro > 0.3 && hypot(b.c.x - a.c.x, b.c.y - a.c.y) < 0.5 { corte[i] = true }
        }

        // Pesos binomiales: la gaussiana discreta más barata que existe.
        var peso = [Double](repeating: 0, count: k + 1)
        for j in 0...k { peso[j] = exp(-Double(j * j) / (2 * Double(k) * Double(k) / 4)) }

        /*
         * Los límites de cada ventana se resuelven con DOS pasadas, no con una
         * búsqueda por muestra. Buscar el corte más cercano dentro del bucle
         * cuesta k por muestra y se notó: el trazo de 600 muestras pasó de 3.7
         * a 11 ms. Un barrido hacia delante y otro hacia atrás dejan la
         * respuesta ya escrita.
         */
        var cortePrevio = [Int](repeating: 0, count: ms.count)
        var corteSiguiente = [Int](repeating: ms.count - 1, count: ms.count)
        var ultimo = 0
        for i in ms.indices { if corte[i] { ultimo = i }; cortePrevio[i] = ultimo }
        var proximo = ms.count - 1
        for i in stride(from: ms.count - 1, through: 0, by: -1) {
            if i + 1 < ms.count && corte[i + 1] { proximo = i }
            corteSiguiente[i] = proximo
        }

        var out = ms
        for i in ms.indices {
            // Sin cruzar cortes, y sin pasarse de los extremos.
            let lo = max(i - k, cortePrevio[i])
            let hi = min(i + k, corteSiguiente[i])
            let alcance = min(i - lo, hi - i)
            guard alcance >= 1 else { continue }
            // El peso decae a cero en las puntas del trazo entero: pulir el
            // extremo lo despunta y acorta.
            let borde = min(Double(i), Double(ms.count - 1 - i)) / Double(k)
            let mezcla = min(1, borde)
            var sx = 0.0, sy = 0.0, sw = 0.0
            for j in -alcance...alcance {
                let w = peso[abs(j)]
                sx += ms[i + j].c.x * w; sy += ms[i + j].c.y * w; sw += w
            }
            out[i].c = CGPoint(x: ms[i].c.x + (sx / sw - ms[i].c.x) * mezcla,
                               y: ms[i].c.y + (sy / sw - ms[i].c.y) * mezcla)
        }

        // Y las tangentes SALEN del centro pulido. Conservar las viejas dejaría
        // el ancho proyectado en una dirección que ya no es la del trazo, que
        // es la mitad del bandeado que esto viene a quitar.
        for i in out.indices where !corte[i] && !(i + 1 < out.count && corte[i + 1]) {
            let a = out[max(0, i - 1)].c, b = out[min(out.count - 1, i + 1)].c
            let dx = b.x - a.x, dy = b.y - a.y
            let m = (dx * dx + dy * dy).squareRoot()
            if m > 1e-9 { out[i].tx = dx / m; out[i].ty = dy / m }
        }
        ms = out
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 3 · entrada y salida
    // ════════════════════════════════════════════════════════════════════════

    /// Adelgaza los extremos. No a cero —una punta de aguja se ve rota— sino a
    /// un suelo, con una ese. Con presión real el efecto es discreto porque la
    /// mano ya entra suave; con un ratón es lo único que distingue un trazo de
    /// una salchicha con dos tapas redondas.
    private static func aplicarEntradaYSalida(_ ms: inout [Muestra], largo: Double, suelo: Double) {
        guard let total = ms.last?.s, total > 1e-6, largo > 1e-6 else { return }
        let l = min(largo, total * 0.45)
        for i in ms.indices {
            let a = ese(min(1, ms[i].s / l))
            let b = ese(min(1, (total - ms[i].s) / l))
            ms[i].h *= suelo + (1 - suelo) * min(a, b)
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 4 · el contorno
    // ════════════════════════════════════════════════════════════════════════

    /// El semiancho de la plumilla en una dirección. Con `e == 1` es el radio
    /// del círculo; con `e > 1` es la función soporte de la elipse, que es la
    /// distancia exacta del centro a la recta de apoyo — la envolvente que
    /// deja una punta ancha al barrer.
    private static func soporte(_ m: Muestra, _ nx: Double, _ ny: Double) -> Double {
        guard m.e > 1.0001 else { return m.h }
        let r = m.e.squareRoot()
        let a = m.h * r, b = m.h / r
        let cu = nx * m.ux + ny * m.uy
        let cv = -nx * m.uy + ny * m.ux
        return (a * a * cu * cu + b * b * cv * cv).squareRoot()
    }

    private static let SEGMENTOS_TAPA = 16

    private static func contorno(_ ms: [Muestra]) -> [CGPoint] {
        var izq: [CGPoint] = [], der: [CGPoint] = []
        izq.reserveCapacity(ms.count); der.reserveCapacity(ms.count)

        for (i, m) in ms.enumerated() {
            // LA JUNTA REDONDA DE LA ESQUINA. Dos muestras en el mismo sitio con
            // tangentes distintas son un vértice: entre las dos hay que girar la
            // plumilla, o el borde de fuera queda con una muesca y el de dentro
            // con un pico. Es el mismo `lineJoin: .round` de toda la vida, pero
            // hecho a mano porque aquí no hay `stroke`, hay un polígono.
            if i > 0 {
                let a = ms[i - 1]
                let cruz = a.tx * m.ty - a.ty * m.tx
                let punto = a.tx * m.tx + a.ty * m.ty
                let giro = atan2(cruz, punto)
                if abs(giro) > 0.3 && hypot(m.c.x - a.c.x, m.c.y - a.c.y) < 0.5 {
                    let pasos = max(2, Int(abs(giro) / 0.22))
                    for k in 1..<pasos {
                        let ang = giro * Double(k) / Double(pasos)
                        let co = cos(ang), si = sin(ang)
                        let tx = a.tx * co - a.ty * si, ty = a.tx * si + a.ty * co
                        var g = m; g.tx = tx; g.ty = ty
                        let nx = -ty, ny = tx
                        let h = soporte(g, nx, ny)
                        izq.append(CGPoint(x: m.c.x + nx * h, y: m.c.y + ny * h))
                        der.append(CGPoint(x: m.c.x - nx * h, y: m.c.y - ny * h))
                    }
                }
            }
            let nx = -m.ty, ny = m.tx
            let h = soporte(m, nx, ny)
            izq.append(CGPoint(x: m.c.x + nx * h, y: m.c.y + ny * h))
            der.append(CGPoint(x: m.c.x - nx * h, y: m.c.y - ny * h))
        }

        var out: [CGPoint] = []
        out.reserveCapacity(izq.count * 2 + SEGMENTOS_TAPA * 2 + 4)
        out.append(contentsOf: izq)
        out.append(contentsOf: tapa(ms[ms.count - 1], entrando: false))
        out.append(contentsOf: der.reversed())
        out.append(contentsOf: tapa(ms[0], entrando: true))
        return out
    }

    /// Media vuelta alrededor del extremo, siguiendo la plumilla. Con la punta
    /// elíptica la tapa NO es un semicírculo: si lo fuera, un trazo inclinado
    /// terminaría en un bulto redondo que delata el truco.
    private static func tapa(_ m: Muestra, entrando: Bool) -> [CGPoint] {
        let nx = -m.ty, ny = m.tx
        // De −N a +N pasando por −T (entrada), o de +N a −N pasando por +T.
        let (ax, ay) = entrando ? (-nx, -ny) : (nx, ny)
        var out: [CGPoint] = []
        out.reserveCapacity(SEGMENTOS_TAPA)
        for k in 1..<SEGMENTOS_TAPA {
            let ang = -Double.pi * Double(k) / Double(SEGMENTOS_TAPA)
            let co = cos(ang), si = sin(ang)
            let dx = ax * co - ay * si
            let dy = ax * si + ay * co
            let h = soporte(m, dx, dy)
            out.append(CGPoint(x: m.c.x + dx * h, y: m.c.y + dy * h))
        }
        return out
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 5 · el camino
    // ════════════════════════════════════════════════════════════════════════

    /// Polígono → camino suave por CUADRÁTICA DE PUNTO MEDIO: cada vértice pasa
    /// a ser el control de una curva que va de un punto medio al siguiente. El
    /// borde queda con tangente continua, así que el contorno no enseña
    /// facetas ni siquiera con el zoom encima — y por eso el camino se puede
    /// CACHEAR sin depender del zoom, que es lo que hace barata la página
    /// entera.
    private static func caminoSuave(_ p: [CGPoint]) -> CGPath {
        let cam = CGMutablePath()
        let n = p.count
        func medio(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        cam.move(to: medio(p[n - 1], p[0]))
        for i in 0..<n {
            cam.addQuadCurve(to: medio(p[i], p[(i + 1) % n]), control: p[i])
        }
        cam.closeSubpath()
        return cam
    }

    /// Un punto de tinta: la pluma bajó y no se movió.
    ///
    /// El SUELO de 0.45 no es decoración. En la tinta real de Daniel hay un
    /// toque guardado con presión CERO —`ink-mt55kmkv-24`, dos muestras en el
    /// mismo sitio— y con la respuesta normal saldría de una unidad de ancho,
    /// o sea invisible. Un toque no tiene recorrido para acumular presión: el
    /// dato dice "cero" porque el sensor no llegó a leer, no porque la mano no
    /// tocara.
    private static func disco(_ q: PuntoTinta, _ o: Opciones, _ d: Double) -> CGPath {
        let u = min(1, max(0, q.p / TOPE_PRESION))
        let f = o.marcador ? 0.85 + 0.30 * u
                           : max(0.45, ANCHO_MIN + (ANCHO_MAX - ANCHO_MIN) * respuesta(u))
        let r = max(0.15, 0.5 * d * f)
        return CGPath(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2),
                      transform: nil)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la caché — NO se portó, y por qué
// ════════════════════════════════════════════════════════════════════════════
//
// sfmap tiene aquí una `CacheTinta` con clave de documento: sus trazos viven en
// una base de datos, se mueven, y el contorno se guarda en coordenadas locales
// para que arrastrarlos no invalide nada.
//
// En SFPoint no hay documento ni trazos que se muevan: un trazo se dibuja, se
// borra entero o se limpia la pizarra. El contorno se guarda dentro del propio
// `Trazo` (ver `Pizarra.swift`), que es más simple y no puede quedar
// desincronizado con una clave. Portar la caché habría sido traerse la MATERIA
// de sfmap en vez del OFICIO.
