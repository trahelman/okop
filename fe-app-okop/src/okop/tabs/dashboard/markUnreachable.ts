import { Okop } from '../../types';

// sing-box keeps the latency of the last successful test, however old, and drops it when a test fails.
// So an outbound is shown unreachable only when the last test on this page failed and it still has no
// latency (a later test elsewhere, e.g. by the fallback guard, may have succeeded).
export function markUnreachable(
  groups: Okop.OutboundGroup[],
  failed: Set<string>,
): Okop.OutboundGroup[] {
  return groups.map((group) => ({
    ...group,
    outbounds: group.outbounds.map((outbound) => ({
      ...outbound,
      unreachable: failed.has(outbound.code) && !outbound.latency,
    })),
  }));
}
