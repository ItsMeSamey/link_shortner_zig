export const site = 'http://127.0.0.1:8080'

interface StorageItem<T> {
  val: T | null
  get: () => T | null
  set: (val: T | null) => void
}

function getStorageItem<T>(key: string, stringify?: (value: T) => string, parser?: (value: string) => T, ): StorageItem<T> {
  const value = localStorage.getItem(key)
  return {
    val: value !== null && value !== undefined && parser ? parser(value) : null,
    get() { return this.val },
    set(val: T | null) {
      if (val === null) {
        localStorage.removeItem(key)
      } else {
        localStorage.setItem(key, stringify ? stringify(val): String(val))
      }
      this.val = val
    },
  }
}

export const loginData = getStorageItem<{method: string, auth: string}>("!Auth", JSON.stringify, JSON.parse)
const methodHash = 'a03f2fd631370334952c5db487ce810e6af747de720ed7a05543a4c1204d3998'

// Encryption functions
async function hash(val: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(val);

  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(byte => byte.toString(16).padStart(2, '0')).join('');

  return hashHex;
}

export async function validateAndSaveCredentials(username: string, password: string) {
  if (await hash(username) !== methodHash)  throw new Error('Invalid username')
  const response = await fetch(site, {
    method: 'POST',
    headers: { 'auth': password }
  })

  if (response.status !== 200) throw new Error('Server error ' + String(response.status))

  loginData.set({ method: username, auth: password })
}

