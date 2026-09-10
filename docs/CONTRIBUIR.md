# Guía de contribución — Community Quest

Esta guía es para las personas del equipo. Las reglas que además deben cumplir los asistentes de
IA están en [`AGENTS.md`](../AGENTS.md), y los principios innegociables del sistema en
[`.specify/memory/constitution.md`](../.specify/memory/constitution.md).

Si solo vas a leer una cosa: **en este proyecto nada se programa sin un spec aprobado**.

---

## 1. Qué es SDD y por qué lo usamos acá

Spec-Driven Development significa que la especificación es el artefacto principal, y el código es
su consecuencia. No es burocracia: en este proyecto todo el antifraude del evento (cooldowns,
techos de puntos, unicidad de actividades, atomicidad del canje) vive en funciones de Postgres
que casi nadie lee de corrido. Sin specs, ese conocimiento existe únicamente en la cabeza de
quien lo escribió.

El ciclo es siempre el mismo:

```
entrevista  ->  spec.md  ->  plan.md  ->  tasks.md  ->  código  ->  PR
  (preguntar)   (qué y por qué)  (cómo)    (pasos)
```

Cada paso se aprueba antes de pasar al siguiente. Un spec con un `[NEEDS CLARIFICATION]` abierto
bloquea el plan; un plan sin aprobar bloquea el código.

**Excepciones**, lo único que no necesita spec: subir dependencias, corregir un typo en un
comentario, y el andamiaje del propio proceso.

## 2. El flujo, paso a paso

### Paso 1 — Especificar

Elegí el siguiente número libre en [`specs/README.md`](../specs/README.md) y creá
`specs/NNN-slug/`. El slug va en inglés y nombra la capacidad, no la implementación
(`reward-claiming`, no `rewards-modal`).

Antes de escribir, **entrevistá**. El spec captura la intención, y la intención no está en el
código: por qué el cooldown es de 5 minutos y no de 3, qué pasa si dos personas canjean el último
premio a la vez, qué queda deliberadamente afuera.

Después copiá [`.specify/templates/spec-template.md`](../.specify/templates/spec-template.md) y
completalo. **En inglés**, describiendo comportamiento observable. Si en un requisito aparece el
nombre de un componente, una tabla o una función, ese requisito está mal escrito: eso va en el
plan.

Todo lo que no sepas se escribe como `[NEEDS CLARIFICATION: la pregunta]`. **Nunca inventes una
regla de negocio.**

### Paso 2 — Revisar

Pasá el spec por [`.specify/checklists/spec-review.md`](../.specify/checklists/spec-review.md).
Un solo ítem sin marcar bloquea la aprobación. Recién ahí el estado pasa a `Approved`.

### Paso 3 — Planificar

Con el spec aprobado, escribí `plan.md`. Acá sí se nombran archivos, tablas, funciones y
paquetes. Empieza por el *constitution check*: si alguna casilla da "No", justificá por escrito, y
si la desviación es permanente, escribí un ADR.

Prestá atención especial a la base de datos: los scripts de `supabase/postgres-init/` corren
**una sola vez, sobre un volumen vacío**. El plan tiene que decir si el cambio exige
`./dev.sh --fresh` en local, un wipe en producción, y si se puede aplicar con un evento en curso.

### Paso 4 — Tareas

`tasks.md` descompone el plan. Una tarea es una unidad revisable con un commit. Cada tarea dice
qué requisito satisface; si no satisface ninguno, no debería existir.

Orden: base de datos, backend, frontend, documentación. Los tests se escriben junto a lo que
prueban, nunca al final.

### Paso 5 — Implementar

Una tarea a la vez, un commit por tarea. Verificás con lint y tests sobre la marcha.

### Paso 6 — Publicar

Recorré [`.specify/checklists/definition-of-done.md`](../.specify/checklists/definition-of-done.md)
completo antes de empujar.

## 3. Ramas

| Rama | Para qué |
|---|---|
| `main` | Lo que está desplegado en un evento. Con tag por release. **Nunca se le hace push sin decidir explícitamente desplegar.** |
| `develop` | La rama de trabajo. Los commits van directo acá. |
| `NNN-slug` | Opcional, para trabajo que convenga aislar. Con el mismo nombre que su carpeta en `specs/` |

Hoy el proyecto lo desarrolla una sola persona, así que **no se exigen pull requests** y el
trabajo se empuja directo a `develop`. Una compuerta de revisión entre alguien y sí mismo no
aporta nada y frena el trabajo.

Lo que **no** cambia por eso:

- Todo cambio de comportamiento sigue necesitando un spec aprobado. El spec es la revisión.
- La Definition of Done sigue aplicando a cada commit, completa.
- A `main` solo entra `develop`, y solo cuando se decide desplegar.
- La historia publicada no se reescribe, y a una rama compartida no se le hace force push.

La plantilla de PR y el archivo CODEOWNERS quedan para cuando el equipo vuelva a crecer.

## 4. Commits

Conventional Commits **en español**, con el emoji del tipo, en imperativo, sin punto final.

```
<tipo>: <emoji> <descripción>
```

| Tipo | Emoji | Cuándo |
|---|---|---|
| `feat` | ✨ | Comportamiento nuevo que el usuario puede ver |
| `fix` | 🐛 | Corregir comportamiento roto |
| `docs` | 📚 | Documentación, specs, ADRs |
| `style` | 💎 | Formato y estilo visual, sin cambio de comportamiento |
| `refactor` | 🔨 | Reestructurar sin cambiar comportamiento |
| `perf` | 🚀 | Rendimiento |
| `test` | 🚨 | Tests |
| `build` | 📦 | Build, Docker, empaquetado |
| `ci` | 👷 | Configuración de CI |
| `chore` | 🔧 | Dependencias, herramientas, mantenimiento |

```
feat: ✨ agregar canje de premios desde el catálogo
fix: 🐛 corregir tolerancia de la ventana temporal del QR
docs: 📚 especificar el registro de participantes
test: 🚨 cubrir la carrera de canjes concurrentes
```

El scope es opcional; si lo usás, que sea el número del spec: `feat(009): ✨ ...`.

**Los emojis van solo en los mensajes de commit.** Nunca en el código, ni en identificadores, ni
en comentarios, ni en logs.

## 5. Nada de firmas de IA

**Ningún commit, PR, comentario ni archivo de este repositorio puede acreditar, mencionar ni
enlazar a un modelo o asistente de IA.**

Prohibido explícitamente:

- Líneas `Co-Authored-By:` con el nombre de un modelo o de un proveedor de IA.
- Pies de "Generated with", "Written by" o "Created with" que nombren una herramienta.
- Enlaces a sesiones de asistentes.
- Comentarios del estilo "generado por IA".

Usá el asistente que quieras. El repositorio registra el trabajo de las personas que lo
publican. Si tu herramienta agrega una firma por defecto, desactivala para este repositorio; los
archivos de reglas de `AGENTS.md` y sus punteros ya se lo indican a Claude, Cursor, Copilot y
Gemini.

Un PR con firma de IA se rechaza y hay que enmendar el commit.

## 6. Cómo verificar tu trabajo

```bash
npm run lint       # ESLint, tiene que quedar limpio
npm test           # Vitest
npm run test:sql   # reglas de negocio contra Postgres, necesita ./dev.sh levantado
```

**No uses `npm run build` para verificar.** Es un paso de release; correrlo en cada cambio solo
te hace perder tiempo.

Para levantar todo el stack local:

```bash
./dev.sh           # Postgres + PostgREST + auth mock + Vite, expuesto en la LAN
./dev.sh --fresh   # borra el volumen de la base y reprovisiona
```

Después de tocar cualquier cosa en `supabase/postgres-init/` **tenés que** correr
`./dev.sh --fresh`: esos scripts corren una sola vez sobre un volumen vacío, y un volumen
existente conserva el esquema viejo.

## 7. Reglas técnicas que no se negocian

Salen de la constitución. Romper una es un PR rechazado, no una discusión.

1. **Las reglas de negocio viven en Postgres.** Una validación que solo existe en JavaScript no
   existe. Los chequeos del cliente son mensajes amables, nunca controles.
2. **La identidad nunca es un parámetro.** Todo RPC resuelve al actor con `auth.uid()`.
3. **Los secretos nunca llegan al cliente.** El secreto HMAC vive en `settings`, una tabla con
   RLS activa y sin ninguna política. Todo lo que esté en una variable `VITE_*` es público.
4. **Toda tabla nueva necesita RLS y políticas explícitas.** Los grants son amplios; el único
   filtro real es RLS.
5. **La economía de puntos se protege estructuralmente**, con un constraint, un índice único o un
   `UPDATE ... WHERE` condicional. Nunca con un `IF`.
6. **Chromium 83 es el piso de compatibilidad.** Nada más nuevo sin un ADR que acepte dejar
   afuera a esa gente.
7. **Nunca commitees secretos.** `.env.prod`, `seed/*.csv` y `data/` están ignorados y siguen así.

## 8. Configuración del repositorio en GitHub

Esto se configura una vez, desde la interfaz de GitHub, y no se puede versionar:

**Settings → Branches → Add branch protection rule**, para `main` y para `develop`:

- Require a pull request before merging
- Require approvals: 1
- Require review from Code Owners
- Require status checks to pass before merging → seleccionar `lint`, `test` y `test-sql`
- Require branches to be up to date before merging
- Do not allow bypassing the above settings
- Restringir force push y borrado de la rama

## 9. Dónde está cada cosa

| Ruta | Qué contiene |
|---|---|
| `AGENTS.md` | Reglas de trabajo, fuente única para humanos y asistentes de IA |
| `.specify/memory/` | Constitución, glosario, arquitectura y ADRs |
| `.specify/templates/` | Plantillas de spec, plan y tareas |
| `.specify/checklists/` | Revisión de specs y Definition of Done |
| `specs/` | Una carpeta por funcionalidad |
| `src/lib/api.js` | El único módulo que habla con el backend |
| `supabase/postgres-init/` | Esquema, RLS y RPC canónicos |
| `auth/server.mjs` | El servicio de autenticación, sin dependencias |
| `tests/sql/` | Tests de reglas de negocio contra una base real |
