@Observed
export class TopicPaginationManager {
  threads: object[] = []
  currentPage: number = 1
  totalPages: number = 0
  hasMore: boolean = true

  prefetchedThreads: object[] = []
  prefetchedPage: number = 0
  prefetchInProgress: boolean = false

  private generation: number = 0

  nextGeneration(): number {
    this.generation++
    return this.generation
  }

  getGeneration(): number {
    return this.generation
  }

  reset(): void {
    this.threads = []
    this.currentPage = 1
    this.totalPages = 0
    this.hasMore = true
    this.prefetchedThreads = []
    this.prefetchedPage = 0
    this.generation = 0
  }

  replaceWith(list: object[], page: number, totalPages: number): void {
    this.threads = list
    this.currentPage = page
    this.totalPages = totalPages
    this.hasMore = page < totalPages
  }

  /**
   * 追加并去重，返回新增项（供 DataSource 使用）
   */
  appendWith(list: object[], page: number): object[] {
    const existingTids: Set<number> = new Set()
    for (let i: number = 0; i < this.threads.length; i++) {
      const t: number = Number((this.threads[i] as Record<string, Object>)['tid'] ?? 0)
      if (t) existingTids.add(t)
    }
    const deduped: object[] = []
    for (let i: number = 0; i < list.length; i++) {
      const t: number = Number((list[i] as Record<string, Object>)['tid'] ?? 0)
      if (!existingTids.has(t)) {
        deduped.push(list[i])
        existingTids.add(t)
      }
    }
    if (deduped.length > 0) {
      const arr: object[] = []
      for (let i: number = 0; i < this.threads.length; i++) arr.push(this.threads[i])
      for (let i: number = 0; i < deduped.length; i++) arr.push(deduped[i])
      this.threads = arr
    }
    this.currentPage = page
    return deduped
  }

  isPrefetchedReady(nextPage: number): boolean {
    return this.prefetchedThreads.length > 0 && this.prefetchedPage === nextPage
  }

  setPrefetched(threads: object[], page: number): void {
    this.prefetchedThreads = threads
    this.prefetchedPage = page
  }

  clearPrefetch(): void {
    this.prefetchedThreads = []
    this.prefetchedPage = 0
  }
}
