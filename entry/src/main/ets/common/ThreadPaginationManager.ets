import { PostInfo } from '../service/NgaApi'

export class ThreadPaginationManager {
  posts: PostInfo[] = []
  pageOfIndex: number[] = []
  loadedLouSet: Set<number> = new Set()
  loadedPageStart: number = 1
  currentPage: number = 1
  totalPages: number = 0
  hasMore: boolean = true

  prefetchedNextPosts: PostInfo[] = []
  prefetchedNextPage: number = 0
  prefetchedNextTotalPages: number = 0

  prefetchedPrevPosts: PostInfo[] = []
  prefetchedPrevPage: number = 0

  private generation: number = 0

  nextGeneration(): number {
    this.generation++
    return this.generation
  }

  getGeneration(): number {
    return this.generation
  }

  reset(): void {
    this.posts = []
    this.pageOfIndex = []
    this.loadedLouSet.clear()
    this.loadedPageStart = 1
    this.currentPage = 1
    this.totalPages = 0
    this.hasMore = true
    this.prefetchedNextPosts = []
    this.prefetchedNextPage = 0
    this.prefetchedNextTotalPages = 0
    this.prefetchedPrevPosts = []
    this.prefetchedPrevPage = 0
  }

  isPrefetchedNextReady(): boolean {
    return this.prefetchedNextPosts.length > 0 && this.prefetchedNextPage > 0
  }

  commitPrefetchedNext(): PostInfo[] {
    if (!this.isPrefetchedNextReady()) return []
    const added: PostInfo[] = this.appendPosts(
      this.prefetchedNextPosts,
      this.prefetchedNextPage,
      this.prefetchedNextTotalPages
    )
    this.prefetchedNextPosts = []
    this.prefetchedNextPage = 0
    this.prefetchedNextTotalPages = 0
    return added
  }

  isPrefetchedPrevReady(): boolean {
    return this.prefetchedPrevPosts.length > 0 && this.prefetchedPrevPage > 0
  }

  commitPrefetchedPrev(): PostInfo[] {
    if (!this.isPrefetchedPrevReady()) return []
    const added: PostInfo[] = this.prependPosts(
      this.prefetchedPrevPosts,
      this.prefetchedPrevPage
    )
    this.prefetchedPrevPosts = []
    this.prefetchedPrevPage = 0
    return added
  }

  replaceWith(newPosts: PostInfo[], page: number, totalPages: number): void {
    this.loadedLouSet.clear()
    for (let i = 0; i < newPosts.length; i++) {
      this.loadedLouSet.add(newPosts[i].lou)
    }
    this.posts = newPosts
    this.pageOfIndex = newPosts.map(() => page)
    this.loadedPageStart = page
    this.currentPage = page
    this.totalPages = totalPages
    this.hasMore = page < totalPages
  }

  appendPosts(rawPosts: PostInfo[], page: number, totalPages: number): PostInfo[] {
    const deduped: PostInfo[] = []
    for (let i = 0; i < rawPosts.length; i++) {
      if (!this.loadedLouSet.has(rawPosts[i].lou)) {
        deduped.push(rawPosts[i])
      }
      this.loadedLouSet.add(rawPosts[i].lou)
    }
    if (deduped.length === 0) {
      this.hasMore = false
      return []
    }
    const combined: PostInfo[] = []
    for (let i = 0; i < this.posts.length; i++) {
      combined.push(this.posts[i])
    }
    for (let i = 0; i < deduped.length; i++) {
      combined.push(deduped[i])
    }
    this.posts = combined

    const newPageOfIndex: number[] = []
    for (let i = 0; i < this.pageOfIndex.length; i++) {
      newPageOfIndex.push(this.pageOfIndex[i])
    }
    for (let i = 0; i < deduped.length; i++) {
      newPageOfIndex.push(page)
    }
    this.pageOfIndex = newPageOfIndex

    this.currentPage = page
    this.totalPages = totalPages
    this.hasMore = page < totalPages
    return deduped
  }

  prependPosts(rawPosts: PostInfo[], page: number): PostInfo[] {
    const deduped: PostInfo[] = []
    for (let i = 0; i < rawPosts.length; i++) {
      if (!this.loadedLouSet.has(rawPosts[i].lou)) {
        deduped.push(rawPosts[i])
      }
      this.loadedLouSet.add(rawPosts[i].lou)
    }
    if (deduped.length === 0) {
      return []
    }
    const combined: PostInfo[] = []
    for (let i = 0; i < deduped.length; i++) {
      combined.push(deduped[i])
    }
    for (let i = 0; i < this.posts.length; i++) {
      combined.push(this.posts[i])
    }
    this.posts = combined

    const newPageOfIndex: number[] = []
    for (let i = 0; i < deduped.length; i++) {
      newPageOfIndex.push(page)
    }
    for (let i = 0; i < this.pageOfIndex.length; i++) {
      newPageOfIndex.push(this.pageOfIndex[i])
    }
    this.pageOfIndex = newPageOfIndex

    this.loadedPageStart = page
    return deduped
  }

  getDisplayPage(centerIndex: number): number {
    if (centerIndex >= 0 && centerIndex < this.pageOfIndex.length) {
      return this.pageOfIndex[centerIndex]
    }
    return this.currentPage
  }

  findPostIndex(pid: number): number {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].pid === pid) {
        return i
      }
    }
    return -1
  }

  updateVoteScore(pid: number, scoreDelta: number, score2Delta: number): number {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].pid === pid) {
        this.posts[i].score += scoreDelta
        this.posts[i].score_2 += score2Delta
        return i
      }
    }
    return -1
  }
}
