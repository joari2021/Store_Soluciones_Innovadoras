# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions

- ...

# Store_Soluciones_Innovadoras

## Sandbox Mercantil C2P Search (solo desarrollo)

Se incorporo una pantalla de pruebas web para el endpoint sandbox de busqueda C2P.

Ruta (solo en development):

- /sandbox/mercantil-c2p-search

Variables de entorno requeridas:

- MERCANTIL_C2P_MERCHANT_ID
- MERCANTIL_C2P_INTEGRATOR_ID
- MERCANTIL_C2P_TERMINAL_ID
- MERCANTIL_C2P_CLIENT_ID
- MERCANTIL_C2P_SECRET_KEY
- MERCANTIL_C2P_ORIGIN_PHONE

Compatibilidad con nombres del playground oficial:

- MERCHANTID
- INTEGRATORID
- TERMINALID
- CLIENTID
- SECRETKEY
- PHONE_NUMBER

## Heroku: reduccion de consumo de RAM (R14)

Configura estos valores para un dyno web pequeno (512 MB):

- WEB_CONCURRENCY=1
- RAILS_MAX_THREADS=3
- RAILS_MIN_THREADS=3
- DB_POOL=3
- MALLOC_ARENA_MAX=2

Comandos sugeridos:

```bash
heroku config:set WEB_CONCURRENCY=1 RAILS_MAX_THREADS=3 RAILS_MIN_THREADS=3 DB_POOL=3 MALLOC_ARENA_MAX=2 -a TU_APP
heroku labs:enable log-runtime-metrics -a TU_APP
heroku ps:scale web=1 -a TU_APP
```

Luego valida consumo:

```bash
heroku logs --tail -a TU_APP
```

Si sigues con R14 luego de estos cambios, reduce temporalmente hilos a 2 o sube el tamano del dyno web.
