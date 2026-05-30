export function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_: (value: T) => void, reject: (reason: Error) => void): void => {
      setTimeout((): void => {
        reject(new Error('timeout'))
      }, ms)
    })
  ])
}
