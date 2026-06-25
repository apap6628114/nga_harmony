/**
 * Increments an AppStorage numeric version key and returns the next value.
 *
 * Version keys are used as lightweight UI refresh signals. Keeping the
 * increment logic centralized prevents local store counters from drifting away
 * from the AppStorage value observed by ArkUI components.
 */
export function bumpAppStorageVersion(key: string): number {
  const next: number = (AppStorage.get<number>(key) ?? 0) + 1
  AppStorage.setOrCreate(key, next)
  return next
}
