import { Logger, DOMAIN_INFRA } from '../utils/Logger'

const logger = new Logger(DOMAIN_INFRA, 'SerialQueue')

export class SerialQueue {
  private last: Promise<void> = Promise.resolve()
  private cancelled: boolean = false

  enqueue(fn: () => Promise<void>): Promise<void> {
    this.last = this.last.then(async (): Promise<void> => {
      if (this.cancelled) return
      await fn()
    }).catch((): void => {
      logger.error('%{public}s', 'SerialQueue: a task failed, chain continued')
    })
    return this.last
  }

  /** 取消队列中所有待执行的任务，当前执行中的任务不受影响 */
  cancel(): void {
    this.cancelled = true
  }

  /** 重置队列，清除已取消标志，后续 enqueue 可继续工作 */
  reset(): void {
    this.cancelled = false
    this.last = Promise.resolve()
  }
}
