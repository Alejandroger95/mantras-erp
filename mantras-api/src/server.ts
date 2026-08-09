import { buildApp } from './app.js'
import { config } from './core/config.js'
import { closeDb } from './core/db.js'

async function main() {
  const app = await buildApp()

  // Cierre limpio: espera que terminen los requests en vuelo
  const shutdown = async (signal: string) => {
    app.log.info(`${signal} recibido — cerrando servidor...`)
    await app.close()
    await closeDb()
    process.exit(0)
  }

  process.on('SIGINT',  () => shutdown('SIGINT'))
  process.on('SIGTERM', () => shutdown('SIGTERM'))

  try {
    await app.listen({ port: config.PORT, host: '0.0.0.0' })
    app.log.info(`🐶 mantras-api corriendo en http://localhost:${config.PORT}`)
  } catch (err) {
    app.log.error(err)
    await closeDb()
    process.exit(1)
  }
}

main()
