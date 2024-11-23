import { openDB, IDBPDatabase } from 'idb'
import { MapEntry, Modification, ModificationType } from './fetch'
import { getStorageItem } from './storageItem'

type dbType = IDBPDatabase<{
  redirections: {
    key: 'location',
    value: MapEntry,
    indexes?: ['destIndex', 'deathatIndex'],
  }
}>

const version = getStorageItem<number>("!Version", String, Number, 1)
var db: dbType | null = null

export async function getDb(): Promise<dbType> {
  if (db !== null) {
    return db
  }
  db = await openDB('!Redirection', version.get()!, {
    upgrade(db) {
      const store = db.createObjectStore('redirections', {
        keyPath: 'location',
      })
      store.createIndex('destIndex', 'dest')
      store.createIndex('deathatIndex', 'deathat')
    },
  })

  return db
}

export async function dbAddRedirection(location: string, dest: string, deathat: Date) {
  const db = await getDb()
  await db.transaction('redirections', 'readwrite').objectStore('redirections').add({ location, dest, deathat })
}

export async function dbDeleteRedirection(location: string) {
  const db = await getDb()
  await db.transaction('redirections', 'readwrite').objectStore('redirections').delete(location)
}

export async function applyModifications(modifications: Modification[]) {
  const promises: Promise<void>[] = []
  for (const modification of modifications) {
    var promise: Promise<void>
    if (modification.modificationType === ModificationType.CREATED) {
      promise = dbAddRedirection(modification.modification.location, modification.modification.dest, new Date(modification.modification.deathat))
    } else {
      promise = dbDeleteRedirection(modification.modification.location)
    }

    promises.push(promise)
  }

  await Promise.all(promises)
}

