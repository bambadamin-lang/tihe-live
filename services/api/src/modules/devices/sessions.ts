/**
 * What "signed in" means for the device limit (ADR-0014), as pure functions so the rule is tested
 * on its own.
 *
 * A device is signed in while it has a session that has not ended and has not timed out. Revoked
 * devices never count: they cannot sign in at all.
 */
export interface DeviceSessionState {
  sessionId: string | null;
  sessionExpiresAt: Date | null;
  revokedAt: Date | null;
}

export function isSignedIn(device: DeviceSessionState, now: Date): boolean {
  return (
    device.revokedAt === null &&
    device.sessionId !== null &&
    device.sessionExpiresAt !== null &&
    device.sessionExpiresAt.getTime() > now.getTime()
  );
}

/** The account's own limit if an admin set one, else the institute default. */
export function effectiveDeviceLimit(
  userMaxDevices: number | null,
  instituteDefault: number,
): number {
  return userMaxDevices ?? instituteDefault;
}

/**
 * Whether one more device may sign in. `others` are the account's other devices, so signing in
 * again on a device that is already signed in never needs a free slot.
 */
export function hasFreeSlot(
  others: readonly DeviceSessionState[],
  limit: number,
  now: Date,
): boolean {
  return others.filter((d) => isSignedIn(d, now)).length < limit;
}
