import { createSelector, createSignal } from 'solid-js'

export interface StorageItem<T> {
  val: T | null
  get: () => T | null
  set: (val: T | null) => void
}

export function getStorageItem<T>(key: string, stringify?: (value: T) => string, parser?: (value: string) => T, defaultValue?: T): StorageItem<T> {
  parser = parser ?? ((x: string) => x as T)
  stringify = stringify ?? ((x: T) => x as string)

  const value = localStorage.getItem(key)
  const retval: StorageItem<T> = {
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

  if (retval.val === null && defaultValue !== undefined) {
    retval.set(defaultValue)
  }

  return retval
}


export const userJwt = getStorageItem<string>('!Jwt')


// Page Navigaion
const [p, setP] = createSignal<string>(userJwt.get()? 'Dashboard': 'Login')
console.log(userJwt.get(), p())
const selectP = createSelector(p)

export { p, setP, selectP }

