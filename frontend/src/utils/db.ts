import { openDB, IDBPDatabase } from 'idb'
import {
  RedirectionInfo,
  Modification,
  ModificationType,
  getLatestModificationIndex,
  getModificationsAfterIndex,
  getRedirectionMapCount,
  getRedirectionMapEntries,
  getOldestModificationIndex
} from './fetch'
import { getStorageItem } from './stateManagement'

type dbType = IDBPDatabase<{
  redirections: {
    key: 'location',
    value: RedirectionInfo,
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

const latestModificationIndex = getStorageItem<number>("!LatestModificationIndex", String, Number, 0)
async function mustAddAllRedirectionsToDb(): Promise<void> {
  const db = await getDb()

  const mindex = await getLatestModificationIndex();
  const count = await getRedirectionMapCount()
  if (count == 0) return;
  for (let i = 0; i < count; i += 1024) {
    const redirections = await getRedirectionMapEntries(i, 1024)
    const os = db.transaction('redirections', 'readwrite').objectStore('redirections')
    for (let j = 0; j < redirections.entries.length; j++) {
      await os.add(redirections.entries[j])
    }
  }

  const newMindex = await getLatestModificationIndex()
  if (newMindex > mindex) {
    const modifications = await getModificationsAfterIndex(mindex)
    await applyModifications(modifications.entries)
  }

  latestModificationIndex.set(newMindex)
}

async function refreshRedirectionRecord(): Promise<void> {
  const idx = await getLatestModificationIndex()

  if (idx == 0) {
    await mustAddAllRedirectionsToDb()
  } else if (idx > latestModificationIndex.get()!) {
    const oldestIndex = await getOldestModificationIndex()
    if (oldestIndex > latestModificationIndex.get()!) {
      await mustAddAllRedirectionsToDb()
    } else {
      const modifications = await getModificationsAfterIndex(latestModificationIndex.get()!)
      await applyModifications(modifications.entries)
      latestModificationIndex.set(idx)
    }
  }
}

export async function getAllRedirectionsDb(): Promise<RedirectionInfo[]> {
  await refreshRedirectionRecord()

  const db = await getDb()
  return await db.transaction('redirections').objectStore('redirections').getAll()
}

