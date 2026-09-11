# Community Quest

Una aplicación web instalable (PWA) para ferias universitarias. Los asistentes recorren los
stands, escanean el código QR que cada stand proyecta, acumulan puntos y los canjean por los
premios que las comunidades traen a sus mesas.

Lo que hace un asistente, de principio a fin: elige un nombre, escanea el QR de un stand y suma
puntos por la visita, participa en las actividades que ese stand organiza y suma más, mira el
ranking, y cuando le alcanza se acerca a la mesa, muestra un código personal y la comunidad le
entrega el premio en mano. No hay correo, ni contraseña, ni registro previo: el nombre y el
teléfono desde el que lo escribió son toda su identidad.

Hay tres roles. El **asistente** juega. La **comunidad** (el stand) proyecta su código, publica sus
actividades y sus premios, y confirma cada entrega. La **organización** monta el evento, da de alta
a las comunidades, resuelve los reclamos y lee el registro de todo lo que pasó.

---

## Índice

- [Cómo está armado](#cómo-está-armado)
- [Para desarrollar](#para-desarrollar)
  - [Requisitos](#requisitos)
  - [Levantar el entorno local](#levantar-el-entorno-local)
  - [Cómo se verifica el trabajo](#cómo-se-verifica-el-trabajo)
  - [Dónde está escrito el resto](#dónde-está-escrito-el-resto)
- [Para operar la feria](#para-operar-la-feria)
  - [1. Secretos](#1-secretos)
  - [2. Arranque](#2-arranque)
  - [3. Contrato con el CDN](#3-contrato-con-el-cdn)
  - [4. Siembra opcional desde CSV](#4-siembra-opcional-desde-csv)
  - [5. Credenciales de los stands](#5-credenciales-de-los-stands)
  - [6. Borrar y volver a desplegar](#6-borrar-y-volver-a-desplegar)

---

## Cómo está armado

Cuatro servicios, ninguno de ellos grande:

| Servicio | Qué es | Para qué |
|---|---|---|
| `web` | Nginx sirviendo el bundle estático | La aplicación que corre en el teléfono |
| `db` | Postgres 16 | Los datos **y todas las reglas del juego** |
| `rest` | PostgREST v12 | Publica la base como API; no decide nada |
| `auth` | Un servicio Node sin dependencias (`auth/server.mjs`) | Usuario y contraseña para stands y organización, sesiones HS256 |

**Las reglas de negocio viven en Postgres**, en funciones `SECURITY DEFINER`
(`supabase/postgres-init/`), no en el cliente. Cuánto vale una visita, cada cuánto se puede repetir,
si una actividad está en curso, si a alguien le alcanza para un premio, quién puede confirmar una
entrega: todo eso se decide en la base. El cliente dibuja y pregunta; no concede nada. Quien tenga
la clave publicable puede llamar a la API directamente, y esa es exactamente la razón por la que
ninguna regla puede vivir del otro lado.

Dos consecuencias que conviene tener presentes al leer el código:

- **La identidad nunca es un parámetro.** Ninguna función acepta "soy este participante": lo
  resuelve con `auth.uid()` a partir del token. Row Level Security acota las lecturas, y los
  privilegios por columna esconden lo que no debe leerse ni siquiera de una tabla pública.
- **Nada corre en segundo plano.** No hay tareas programadas ni servicio de tiempo real. El estado
  de una actividad, la vigencia de un código de canje y todo lo demás se **derivan** al momento de
  preguntarlo; el ranking se refresca por sondeo cada cinco segundos.

---

## Para desarrollar

### Requisitos

| Herramienta | Versión | Por qué esa |
|---|---|---|
| Node.js | 24 | Todas las imágenes están fijadas a `node:24-alpine`. Vite 8 no soporta por debajo de Node 20.19 |
| Docker + Docker Compose | Cualquiera reciente | El entorno local levanta Postgres, PostgREST y el servicio de auth |
| React | 19 | |
| Vite | 8 | |
| Vitest | 5 | |
| ESLint | 10 | Configuración plana (`eslint.config.js`) |

**El piso de compatibilidad es Chromium 83.** No es una cifra elegida por gusto: el dispositivo más
antiguo del público objetivo corre Bromite, que es Chromium 83. Está impuesto en `vite.config.js`
con `build.target: 'chrome83'` y `cssTarget: 'chrome83'`, y significa que el código que se publica
no puede usar sintaxis posterior. Es la razón por la que verás patrones que hoy se escribirían de
otra forma.

### Levantar el entorno local

```bash
./dev.sh            # Postgres + PostgREST + auth + Vite, expuesto en la LAN
./dev.sh --fresh    # borra el volumen de la base y vuelve a provisionar
```

El script genera `.dev/` a partir de los **mismos archivos SQL que se despliegan en producción**
(`supabase/postgres-init/`), y corre el mismo `auth/server.mjs`. Esto no es un detalle: cuando el
entorno local tenía su propio servicio de auth simulado, tres errores distintos salieron de que
dev y producción no fueran lo mismo, y dos de ellos en el camino de las credenciales.

El script imprime al final las credenciales de demostración de cada stand y de la organización, y
la dirección de LAN por la que un teléfono real puede entrar. La cámara necesita HTTPS, así que
desde otro dispositivo conviene probar con el código manual de seis caracteres.

> **Un cambio de esquema exige una base nueva.** Los scripts de inicialización de Postgres corren
> una sola vez, sobre un volumen vacío. Si tocas `supabase/postgres-init/`, corre `./dev.sh --fresh`
> una vez; si no, seguirás trabajando contra el esquema viejo y el síntoma aparecerá lejos de la
> causa.

### Cómo se verifica el trabajo

```bash
npm run lint        # ESLint, falla con cualquier aviso
npm test            # Vitest
npm run test:sql    # las reglas de negocio, contra un Postgres real
```

`npm run test:sql` construye una base descartable **desde los scripts canónicos de producción** y
corre las suites de `tests/sql/`. No hay simulaciones: una simulación de `validate_and_scan` no
demostraría nada sobre la función que de verdad corre durante la feria. Necesita el entorno local
levantado, o `PSQL_CMD` apuntando a cualquier servidor alcanzable.

> **`npm run build` no es una forma de verificar.** Que el bundle se arme no dice nada sobre si las
> reglas se cumplen. La compilación pertenece al despliegue; el trabajo se verifica con las tres
> compuertas de arriba.

Un test que nunca estuvo en rojo no demuestra nada: al escribir una aserción, rompe a propósito la
regla que dice cubrir y comprueba que falla.

### Dónde está escrito el resto

Este archivo explica qué es el sistema y cómo se corre. Todo lo demás vive en su lugar, y se
enlaza en vez de copiarse, porque dos versiones de la misma regla terminan contradiciéndose:

| Dónde | Qué hay |
|---|---|
| [`specs/`](specs/) | Las especificaciones, una por flujo, con su estado. [`specs/README.md`](specs/README.md) es el índice |
| [`AGENTS.md`](AGENTS.md) | Las reglas de trabajo del equipo: ramas, commits, Definition of Done. Fuente única, también para los asistentes de IA |
| [`.specify/memory/constitution.md`](.specify/memory/constitution.md) | Los principios que ningún cambio puede romper |
| [`.specify/memory/decisions/`](.specify/memory/decisions/) | Por qué el sistema es así y no de otra forma |
| [`docs/CONTRIBUIR.md`](docs/CONTRIBUIR.md) | La guía práctica de contribución |
| [`.specify/memory/glossary.md`](.specify/memory/glossary.md) | El glosario del dominio, español e inglés: las specs están en inglés y la interfaz en español |

El proyecto usa **desarrollo guiado por especificaciones**: un cambio de comportamiento se escribe
primero como spec y recién después como código. Si vas a cambiar cómo se comporta algo y no
encuentras su spec, escríbela antes.

---

## Para operar la feria

El `docker-compose.yml` está orientado a producción: los cuatro servicios, sin pasarela. **El
enrutado y el TLS los hace tu CDN existente** contra los puertos publicados; en este repositorio no
hay certificados. El backend es efímero por diseño: corre unas horas y se apaga.

### 1. Secretos

```bash
SITE_URL=https://feria.ejemplo.test ./deploy-keys.sh   # genera .env.prod con permisos 600
```

`.env.prod` no se versiona nunca. `POSTGRES_PASSWORD` es hexadecimal porque viaja dentro de cadenas
de conexión. Para rotar, `--force`, y después `down` y borrar `./data/db`: la contraseña de la base
queda fijada en la inicialización.

`deploy-keys.sh` genera también el usuario de la organización (`ORGANIZER_USERNAME` /
`ORGANIZER_PASSWORD`). **Se escribe en la base solo en el primer arranque de un `./data/db` vacío.**
Volver a generar `.env.prod` con el volumen ya existente deja la contraseña impresa sin efecto, y
el panel responde *"Credenciales incorrectas"*. Para aplicar credenciales nuevas, borra `./data/db`
(sección 6) o actualiza el hash almacenado:

```sql
UPDATE organizers
SET password_hash = crypt('<contraseña-de-organizacion>', gen_salt('bf', 12))
WHERE username = '<usuario-de-organizacion>';
```

La organización entra por su propia dirección, `https://<origen>/#/organizador/entrar` (la
aplicación usa enrutado por hash). No está enlazada desde ninguna pantalla de stand ni de
asistente, a propósito. La pantalla de stand (`/#/admin/login`) acepta solo cuentas de stand: las
credenciales de organización se rechazan ahí con un mensaje que indica por dónde entrar.

**Las comunidades se crean desde el panel**, en la sección Comunidades: la organización da de alta
el stand y el sistema genera una contraseña que se muestra **una sola vez**. No hay forma de volver
a verla, solo de restablecerla. Cada comunidad publica después sus propias actividades y sus
propios premios desde su consola; la organización puede corregir precios, existencias y bajas, pero
no registra premios en nombre de nadie.

### 2. Arranque

```bash
docker compose --env-file .env.prod up -d --build
```

En el primer arranque, la inicialización de Postgres carga el esquema, las políticas y las
funciones, y siembra cuentas desde `./seed/*.csv` si los archivos están presentes (ambos son
opcionales, ver sección 4). Con `./seed` vacío se crea únicamente la cuenta de organización y los
stands se agregan desde el panel.

Los scripts de inicialización corren en orden numérico, así que una siembra mal formada que aborte
impide también que se cree la cuenta de organización. Se escribe una marca de finalización solo
cuando toda la cadena termina bien, y el `healthcheck` de `db` la exige: si la inicialización
abortó, la base queda `unhealthy` y la API nunca arranca contra una base a medio construir. **Lee
los registros de la base antes de confiar en el primer arranque.**

```bash
curl -s http://localhost:9999/health
curl -s -H "apikey: $ANON" http://localhost:3000/communities?select=name
docker compose --env-file .env.prod exec db psql -U postgres
```

### 3. Contrato con el CDN

Despliega `nginx-cdn.conf.example` en tu CDN y apunta los tres upstreams a la IP del host de Docker
y a los puertos publicados (`WEB/REST/AUTH_PORT`). Un mismo origen público sirve todas las rutas, y
ahí termina el TLS:

| Ruta | Destino |
|---|---|
| `/rest/v1/*` | PostgREST (los GET con 200 se microcachean 5 s) |
| `/auth/v1/*` | Servicio de auth (nunca se cachea) |
| `/*` | La aplicación |

El microcaché está en el ejemplo: 5 s de vida, cerrojo contra estampida, `stale-while-revalidate` y
claves por sesión. Es lo que absorbe el sondeo del ranking. Para comprobarlo a través del CDN:

```bash
curl -sI -H "apikey: $ANON" https://feria.ejemplo.test/rest/v1/communities?select=name | grep -i x-microcache
# la primera vez MISS, después HIT
```

`VITE_SUPABASE_URL` tiene que ser el origen público `https://`. Vite lo incrusta durante
`docker build`, así que cambiar de dominio obliga a reconstruir con `--build`.

### 4. Siembra opcional desde CSV

Los dos archivos son opcionales: con `./seed` vacío, el primer arranque crea solo la cuenta de
organización y todo lo demás se agrega desde el panel. Para precargarlos, copia los ejemplos
versionados y edita las copias — `seed/*.csv` está en `.gitignore` porque contiene contraseñas en
claro, así que solo se versionan los `.example`:

```bash
cp seed/stands.csv.example seed/stands.csv
cp seed/rewards.csv.example seed/rewards.csv
chmod 600 seed/stands.csv
# y después edita ambos
```

No hay ninguna cuenta escrita a mano en el SQL.

`seed/stands.csv`, cabecera `user,pw,name`:

```csv
user,pw,name
stand-uno,<contraseña-1>,Nombre De La Comunidad
```

`seed/rewards.csv`, cabecera `stand,name,description,cost,stock,emoji`, donde `stand` coincide con
un `user` del archivo anterior. Se admite dejarlo con solo la cabecera si no quieres precargar
premios:

```csv
stand,name,description,cost,stock,emoji
stand-uno,Nombre del premio,Una descripción corta,150,1,Box
```

Reglas: UTF-8, y entrecomilla los campos que contengan comas. Las filas con `user` o `pw` vacíos se
ignoran; las que tengan `name` o `cost` vacíos abortan la siembra de forma visible.

**Los archivos se leen una sola vez**, en la inicialización de Postgres sobre un `./data/db` vacío:
sirven para provisionar un despliegue nuevo, nada más. Para crear o cambiar cuentas en una
instancia en marcha se usa el panel de organización (o la rotación por SQL de la sección 5). Nunca
borres una base viva para volver a sembrarla.

### 5. Credenciales de los stands

Las cuentas sembradas son las que pusiste en `seed/stands.csv`; entrega cada par `user,pw` a su
stand por un canal seguro. Las creadas desde el panel muestran su contraseña una sola vez. No hay
recuperación por correo: para rotar una contraseña en una instancia en marcha, usa el panel, o SQL:

```sql
UPDATE communities
SET password_hash = crypt('<contraseña-nueva>', gen_salt('bf', 12))
WHERE username = '<usuario-del-stand>';
```

El coste 12 no es decorativo: el valor por omisión de `gen_salt('bf')` es 6, que se rompe sin
esfuerzo fuera de línea.

### 6. Borrar y volver a desplegar

```bash
docker compose --env-file .env.prod down
rm -rf ./data/db   # DESTRUCTIVO: la inicialización y la siembra vuelven a correr
```

Un borrado vuelve a crear la organización con los `ORGANIZER_*` que haya en `.env.prod` y repite la
siembra desde CSV. Los datos de la base viven en `./data/db`, montado del host y fuera del control
de versiones.

---

Todos los dominios, usuarios y contraseñas de este archivo son marcadores de posición. Ninguno
funciona si se pega tal cual, que es justamente la idea.
