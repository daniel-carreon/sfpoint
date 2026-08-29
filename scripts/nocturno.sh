#!/bin/bash
# nocturno.sh — retoma el modo lápiz de SFPoint si la sesión de Levy se cortó.
#
# POR QUÉ EXISTE: Daniel pidió el trabajo "aunque me corte el usage" (28 ago, 21:00).
# Un cron de sesión muere con la sesión; esto vive en launchd y sobrevive.
#
# TRES CANDADOS, en orden, para no correr dos agentes sobre el mismo repo:
#   1. ESTADO: TERMINADO en PLAN-lapiz.md  → no hay nada que hacer.
#   2. LATIDO fresco (< 25 min)            → la sesión viva sigue trabajando.
#   3. lockfile con PID vivo               → ya hay un nocturno corriendo.
set -u
REPO="$HOME/Developer/software/sfpoint"
PLAN="$REPO/PLAN-lapiz.md"
LOCK="/tmp/sfpoint-lapiz-nocturno.lock"
LOG="/tmp/sfpoint-lapiz-nocturno.log"
say() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

[ -f "$PLAN" ] || { say "sin PLAN-lapiz.md — nada que retomar"; exit 0; }

if grep -q '^> \*\*ESTADO:\*\* TERMINADO' "$PLAN"; then
  say "ESTADO=TERMINADO — no corro"; exit 0
fi

# El latido lo escribe la sesión viva mientras trabaja.
LATIDO=$(grep -m1 '^> \*\*ULTIMO_LATIDO:\*\*' "$PLAN" | sed 's/.*ULTIMO_LATIDO:\*\* *//' | tr -d ' ')
if [ -n "${LATIDO:-}" ]; then
  T=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$LATIDO" +%s 2>/dev/null || echo 0)
  AHORA=$(date +%s)
  if [ "$T" -gt 0 ] && [ $((AHORA - T)) -lt 1500 ]; then
    say "latido fresco ($((AHORA - T))s) — la sesión viva sigue; no corro"; exit 0
  fi
fi

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  say "ya hay un nocturno vivo (pid $(cat "$LOCK")) — no corro"; exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

say "=== ARRANCA nocturno (la sesión de Levy no dio señales) ==="
cd "$REPO" || exit 1

PROMPT='Eres Levy trabajando en el repo ~/Developer/software/sfpoint (rama swift).
Daniel pidió el MODO LÁPIZ de SFPoint y la sesión que lo estaba construyendo se cortó por cuota.
LEE ~/Developer/software/sfpoint/PLAN-lapiz.md COMPLETO: ahí está el encargo verbatim, las
decisiones ya firmadas y el checklist con lo que falta. Lee también ~/Developer/software/sfpoint/CLAUDE.md
(invariantes que no se rompen) y el motor de tinta en ~/Developer/software/sfmap/Sources/SFMap/Tinta.swift.
CONTINÚA desde el primer punto sin marcar del checklist hasta terminarlo TODO: compilar limpio,
verificar headless (nada de abrir ventanas encima de Daniel: está durmiendo/trabajando), firmar con
la identidad SFlow Dev, instalar en /Applications, actualizar CLAUDE.md/README, y commit+push.
Marca cada punto del checklist conforme lo cierres y actualiza ULTIMO_LATIDO en cada avance.
Cuando de verdad esté todo hecho y verificado, cambia la primera línea a "> **ESTADO:** TERMINADO".
No preguntes nada: decide y ejecuta.'

/opt/homebrew/bin/claude -p "$PROMPT" \
  --permission-mode bypassPermissions \
  --model opus \
  >> "$LOG" 2>&1
say "=== FIN nocturno (exit $?) ==="
