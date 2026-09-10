# Cuentas de siembra

Los archivos `*.example` de este directorio están versionados. Los `*.csv` reales
**no**: contienen contraseñas en texto plano y `seed/*.csv` está en `.gitignore`.

Para precargar stands y premios en un despliegue nuevo, copia y edita:

```bash
cp seed/stands.csv.example seed/stands.csv
cp seed/rewards.csv.example seed/rewards.csv
chmod 600 seed/stands.csv
```

- `stands.csv` — cabecera `user,pw,name`. Una fila por stand. `user` y `pw` son
  las credenciales que se le entregan al stand.
- `rewards.csv` — cabecera `stand,name,description,cost,stock,emoji`. Puede tener
  solo la cabecera si cada stand carga sus propios premios. `stand` debe coincidir
  con un `user` del archivo anterior.

Ambos archivos son opcionales. Si `seed/` no tiene ningún `.csv`, el primer arranque
continúa normalmente: no se carga ningún stand y la única cuenta activa es la del
organizador; los stands se crean después desde el panel. Un archivo presente pero mal
formado sí aborta la inicialización, y entonces el `db` queda `unhealthy` (falta el
marcador de inicialización) y la API no arranca contra una base vacía. Ver la sección 4
del `README.md`.

Después del primer arranque las contraseñas viven solo como hash bcrypt en la base.
Los CSV se pueden borrar del host, pero guarda las credenciales en un lugar seguro:
no se pueden recuperar del sistema.
