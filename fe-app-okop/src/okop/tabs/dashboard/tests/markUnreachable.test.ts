import { describe, expect, it } from 'vitest';
import { markUnreachable } from '../markUnreachable';
import { Okop } from '../../../types';

function outbound(code: string, latency: number): Okop.Outbound {
  return { code, displayName: code, latency, type: 'Direct', selected: true };
}

function group(...outbounds: Okop.Outbound[]): Okop.OutboundGroup {
  return { withTagSelect: false, code: 'card', displayName: 'card', outbounds };
}

describe('markUnreachable', () => {
  it('marks an outbound whose test failed', () => {
    const [card] = markUnreachable(
      [group(outbound('vpn-out', 0))],
      new Set(['vpn-out']),
    );

    expect(card.outbounds[0].unreachable).toBe(true);
  });

  it('keeps an outbound that has a latency again', () => {
    const [card] = markUnreachable(
      [group(outbound('vpn-out', 120))],
      new Set(['vpn-out']),
    );

    expect(card.outbounds[0].unreachable).toBe(false);
  });

  it('does not mark an outbound whose test did not fail', () => {
    const [card] = markUnreachable(
      [group(outbound('vpn-out', 0), outbound('proxy-out', 0))],
      new Set(['proxy-out']),
    );

    expect(card.outbounds.map((item) => item.unreachable)).toEqual([
      false,
      true,
    ]);
  });
});
