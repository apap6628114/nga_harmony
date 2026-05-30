export class CacheEntry<V> {
  value: V | undefined = undefined
  stale: boolean = false
}

export class LruCache<V> {
  private maxSize: number
  private ttlMs: number
  private map: Map<string, V> = new Map()
  private order: string[] = []
  private timestamps: Map<string, number> = new Map()

  constructor(maxSize: number, ttlMs: number = 0) {
    this.maxSize = maxSize
    this.ttlMs = ttlMs
  }

  get(key: string): V | undefined {
    const ts = this.timestamps.get(key)
    if (ts !== undefined && this.ttlMs > 0 && Date.now() - ts > this.ttlMs) {
      this.delete(key)
      return undefined
    }
    const val = this.map.get(key)
    if (val !== undefined) {
      this.touch(key)
    }
    return val
  }

  set(key: string, value: V): void {
    if (this.map.has(key)) {
      this.map.set(key, value)
      this.timestamps.set(key, Date.now())
      this.touch(key)
    } else {
      if (this.map.size >= this.maxSize) {
        const oldest: string | undefined = this.order.shift()
        if (oldest !== undefined) {
          this.map.delete(oldest)
          this.timestamps.delete(oldest)
        }
      }
      this.map.set(key, value)
      this.order.push(key)
      this.timestamps.set(key, Date.now())
    }
  }

  delete(key: string): void {
    this.map.delete(key)
    this.timestamps.delete(key)
    const idx: number = this.order.indexOf(key)
    if (idx >= 0) {
      this.order.splice(idx, 1)
    }
  }

  clear(): void {
    this.map.clear()
    this.order = []
    this.timestamps.clear()
  }

  has(key: string): boolean {
    return this.map.has(key)
  }

  getWithStale(key: string): CacheEntry<V> {
    const val: V | undefined = this.map.get(key)
    if (val === undefined) {
      const entry1: CacheEntry<V> = new CacheEntry<V>()
      entry1.value = undefined
      entry1.stale = false
      return entry1
    }
    const ts: number | undefined = this.timestamps.get(key)
    if (this.ttlMs > 0 && ts !== undefined && Date.now() - ts > this.ttlMs) {
      const entry2: CacheEntry<V> = new CacheEntry<V>()
      entry2.value = val
      entry2.stale = true
      return entry2
    }
    this.touch(key)
    const entry3: CacheEntry<V> = new CacheEntry<V>()
    entry3.value = val
    entry3.stale = false
    return entry3
  }

  isFresh(key: string): boolean {
    const ts: number | undefined = this.timestamps.get(key)
    if (ts === undefined) return false
    if (this.ttlMs > 0 && Date.now() - ts > this.ttlMs) return false
    return this.map.has(key)
  }

  get size(): number {
    return this.map.size
  }

  keys(): string[] {
    const result: string[] = []
    for (let i = 0; i < this.order.length; i++) {
      result.push(this.order[i])
    }
    return result
  }

  private touch(key: string): void {
    const idx: number = this.order.indexOf(key)
    if (idx >= 0) {
      this.order.splice(idx, 1)
      this.order.push(key)
    }
  }
}
