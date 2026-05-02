export class FilterListManager<T> {
  private items: T[] = []

  init(list: T[]): void {
    this.items = list
  }

  getList(): T[] {
    return this.items
  }

  add(item: T): T[] {
    this.items = [...this.items, item]
    return this.items
  }

  remove(predicate: (item: T) => boolean): T[] {
    this.items = this.items.filter(i => !predicate(i))
    return this.items
  }

  clear(): T[] {
    this.items = []
    return this.items
  }
}
