export interface StorageItem<T> {
  val: T | null
  get: () => T | null
  set: (val: T | null) => void
}

export function getStorageItem<T>(key: string, stringify?: (value: T) => string, parser?: (value: string) => T, defaultValue?: T): StorageItem<T> {
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

