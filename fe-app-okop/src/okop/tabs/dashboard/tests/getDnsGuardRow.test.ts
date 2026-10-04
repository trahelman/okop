import { describe, expect, it } from 'vitest';
import { getDnsGuardRow } from '../getDnsGuardRow';
import { formatSince } from '../../../../helpers/formatSince';
import { Okop } from '../../../types';

function status(
  patch: Partial<Okop.GetDnsGuardStatus>,
): Okop.GetDnsGuardStatus {
  return {
    running: 1,
    state: 'ok',
    since: 0,
    manage_dnsmasq: 1,
    ...patch,
  };
}

const NOW = new Date(2026, 9, 3, 19, 45);
const TODAY = Math.floor(new Date(2026, 9, 3, 19, 30).getTime() / 1000);
const YESTERDAY = Math.floor(new Date(2026, 9, 2, 23, 10).getTime() / 1000);

describe('formatSince', () => {
  it('gives nothing while the time is unknown', () => {
    expect(formatSince(0, NOW)).toBe('');
  });

  it('gives only the time for today', () => {
    expect(formatSince(TODAY, NOW)).toBe(
      new Date(TODAY * 1000).toLocaleTimeString(undefined, {
        hour: '2-digit',
        minute: '2-digit',
      }),
    );
  });

  it('adds the date for an earlier day', () => {
    expect(formatSince(YESTERDAY, NOW)).not.toBe(formatSince(TODAY, NOW));
    expect(formatSince(YESTERDAY, NOW)).toContain('2');
  });
});

describe('getDnsGuardRow', () => {
  it('shows a working guard in green without a hint', () => {
    const row = getDnsGuardRow(status({ since: TODAY }), NOW);

    expect(row.value).toBe('✔ Working');
    expect(row.hint).toBeUndefined();
    expect(row.attributes.class).toContain('--success');
  });

  it('says dnsmasq is left alone with "Dont Touch My DHCP!"', () => {
    const row = getDnsGuardRow(status({ manage_dnsmasq: 0 }), NOW);

    expect(row.hint).toContain('Dont Touch My DHCP!');
  });

  it('shows sing-box down with the time of the switch', () => {
    const row = getDnsGuardRow(
      status({ state: 'sing_box_down', since: TODAY }),
      NOW,
    );

    expect(row.value).toBe(
      `⚠ sing-box is not responding since ${formatSince(TODAY, NOW)}`,
    );
    expect(row.hint).toBe('DNS and traffic to the lists go directly');
    expect(row.attributes.class).toContain('--warning');
  });

  it('leaves the time out while the guard has not recorded it', () => {
    const row = getDnsGuardRow(status({ state: 'dns_server_down' }), NOW);

    expect(row.value).toBe('⚠ sing-box DNS server is unreachable');
  });

  it('mentions only the lists when dnsmasq is not switched', () => {
    const row = getDnsGuardRow(
      status({ state: 'sing_box_down', manage_dnsmasq: 0 }),
      NOW,
    );

    expect(row.hint).toBe('Traffic to the lists goes directly');
  });

  it('shows a stopped guard in red', () => {
    const row = getDnsGuardRow(status({ state: 'stopped', running: 0 }), NOW);

    expect(row.value).toBe('✘ Not running');
    expect(row.attributes.class).toContain('--error');
  });
});
