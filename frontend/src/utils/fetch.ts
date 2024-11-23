import { getStorageItem } from "./storageItem";

export const site = 'http://127.0.0.1:8080/'

export const loginData = getStorageItem<{method: string, auth: string}>("!Auth", JSON.stringify, JSON.parse)
const methodHash = 'a03f2fd631370334952c5db487ce810e6af747de720ed7a05543a4c1204d3998'

export const modificationIndex = getStorageItem<number>("!ModificationIndex", String, Number)
if (modificationIndex.get() === null) {
  getOldestModificationIndex().then(modificationIndex.set).catch(console.error)
}

// Hashes a string using SHA-256
async function hash(val: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(val);

  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(byte => byte.toString(16).padStart(2, '0')).join('');

  return hashHex;
}

// Validate and save the credentials to the loginData (in localStorage)
export async function validateAndSaveCredentials(username: string, password: string) {
  if (await hash(username) !== methodHash)  throw new Error('Invalid username')
  const response = await fetch(site, {
    method: 'POST',
    headers: [
      ['auth', password],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))

  loginData.set({ method: username, auth: password })
}

// @param from: the location that will be redirected
// @param to: where the site should redirect to
// @param lifetime: The lifetime of the entries in seconds
//
// @throws Error if the server returns an error
export async function addRedirection(from: string, to: string, lifetime: number) {
  const response = await fetch(site +  from, {
    method: loginData.get()!.method + '0',
    headers: [
      ['auth', loginData.get()!.auth],
      ['dest', to],
      ['death', String(lifetime)],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))
}

// @param from: the location that will be redirected
//
// @throws Error if the server returns an error
export async function deleteRedirection(from: string) {
  const response = await fetch(site + from, {
    method: loginData.get()!.method + '1',
    headers: [
      ['auth', loginData.get()!.auth],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))
}

// Returns the number of entries in the redirection map
//
// @throws Error if the server returns an error
export async function getRedirectionMapCount(): Promise<number> {
  const response = await fetch(site, {
    method: loginData.get()!.method + '0',
    headers: { auth: loginData.get()!.auth }
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))

  return Number(await response.text())
}

export interface MapEntry {
  location: string
  dest: string
  deathat: number
}

// @param from: the location that will be redirected
// @param count: the number of entries to be returned
//
// @throws Error if the server returns an error
export async function getRedirectionMapEntries(from: number, count: number): Promise<{entries: MapEntry[], nextIndex: number}> {
  const response = await fetch(site + String(from) + '.' + String(count), {
    method: loginData.get()!.method + '2',
    headers:[
      ['auth', loginData.get()!.auth],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))

  const body = await response.text()
  const entryStrings = body.split('\n')
  const nextIndex = Number(entryStrings.pop()!)
  const entries: MapEntry[] = []
  for (let i = 0; i < entryStrings.length; i++) {
    const [deathat, location, dest] = entryStrings[i].split('\0')
    entries.push({ deathat: Number(deathat), location, dest })
  }

  return { entries, nextIndex }
}

// Returns the oldest modification date of the site
//
// @throws Error if the server returns an error
export async function getOldestModificationIndex(): Promise<number> {
  const response = await fetch(site, {
    method: loginData.get()!.method + '1',
    headers: [
      ['auth', loginData.get()!.auth],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))
  return Number(await response.text())
}

export enum ModificationType {
  CREATED,
  DELETED,
}

export interface Modification {
  index: number
  modificationType: ModificationType
  modification: MapEntry
}

function parseModification(text: string): {entries: Modification[], oldestIndex: number} {
  if (text.length == 0) return {entries: [], oldestIndex: 0}

  const midificationStrings = text.split('\n')
  const oldestIndex = Number(midificationStrings.pop()!)
  const modifications: Modification[] = []

  for (let i = 0; i < midificationStrings.length; i++) {
    let type: ModificationType
    if (midificationStrings[i].charAt(0) === '+') {
      type = ModificationType.CREATED
    } else if (midificationStrings[i].charAt(0) === '-') {
      type = ModificationType.DELETED
    } else {
      continue
    }
    const [index, deathat, location, dest] = midificationStrings[i].substring(1).split('\0')
    modifications.push({ index: Number(index), modificationType: type, modification: { deathat: Number(deathat), location, dest } })
  }

  return { entries: modifications, oldestIndex }
}

export async function getAllModifications(): Promise<{entries: Modification[], oldestIndex: number}> {
  const response = await fetch(site, {
    method: loginData.get()!.method + '3',
    headers: [
      ['auth', loginData.get()!.auth],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))
  return parseModification(await response.text())
}

// Returns all the modification after the given date
//
// @throws Error if the server returns an error
export async function getModificationsAfterIndex(index: number): Promise<{entries: Modification[], oldestIndex: number}> {
  const response = await fetch(site + String(index), {
    method: loginData.get()!.method + '3',
    headers: [
      ['auth', loginData.get()!.auth],
    ],
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))
  return parseModification(await response.text())
}

(globalThis as any).fetchingFunctions = [
  addRedirection,
  deleteRedirection,
  getRedirectionMapCount,
  getRedirectionMapEntries,
  getOldestModificationIndex,
  getModificationsAfterIndex,
]

