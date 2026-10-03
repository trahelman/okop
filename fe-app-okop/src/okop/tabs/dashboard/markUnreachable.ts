import { Okop } from '../../types';

// sing-box keeps the latency of the last successful test, however old, and drops it when a test fails.
// So only an outbound a test on this page covered and that has no latency is known not to respond.
export function markUnreachable(
  groups: Okop.OutboundGroup[],
  tested: Set<string>,
): Okop.OutboundGroup[] {
  return groups.map((group) => ({
    ...group,
    outbounds: group.outbounds.map((outbound) => ({
      ...outbound,
      unreachable: tested.has(outbound.code) && !outbound.latency,
    })),
  }));
}
