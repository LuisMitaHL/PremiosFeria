## Spec

<!-- Enlaza el spec que respalda este cambio. Sin spec aprobado no se mergea, salvo que sea
     un bump de dependencias, una corrección de typo en comentarios, o andamiaje del proceso. -->

Spec: `specs/NNN-slug/spec.md`

## Qué cambia

<!-- En dos o tres frases y en términos de comportamiento observable, no de archivos tocados. -->

## Criterios de aceptación

<!-- Copia aquí la sección 8 del spec y marca cada línea que verificaste. -->

- [ ]
- [ ]

## Base de datos

- [ ] Este cambio **no** toca `supabase/postgres-init/`
- [ ] Toca el esquema y **requiere wipe** (`./dev.sh --fresh` en local, borrar `./data/db` en producción)
- [ ] Toca el esquema y **se puede aplicar con un evento en curso**

## Verificación

- [ ] `npm run lint` sin errores
- [ ] `npm test` en verde
- [ ] `npm run test:sql` en verde contra una base levantada con `./dev.sh`
- [ ] CI en verde
- [ ] Recorrido manual de los flujos afectados

<!-- No uses `npm run build` para verificar: es un paso de release, no una compuerta. -->

## Definition of Done

- [ ] Recorrí `.specify/checklists/definition-of-done.md` completo
- [ ] No se agregó ningún secreto ni dato real de seed a un archivo versionado
- [ ] Ninguna regla de negocio se movió de Postgres al cliente
- [ ] Ningún RPC recibe la identidad del llamador como parámetro
- [ ] Las tablas nuevas tienen RLS y políticas explícitas
- [ ] No se introdujo sintaxis ni APIs posteriores a Chromium 83
- [ ] No hay emojis en el código fuente
- [ ] Los commits siguen el formato en español con emoji

## Atribución

- [ ] **Confirmo que ni los commits, ni esta descripción, ni el código contienen atribución a
      modelos o asistentes de IA** (sin `Co-Authored-By` de modelos, sin pies de "Generated
      with", sin enlaces de sesión)
