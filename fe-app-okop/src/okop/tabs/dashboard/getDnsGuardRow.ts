import { Okop } from '../../types';

export interface DnsGuardRow {
  key: string;
  value: string;
  hint?: string;
  attributes: { class: string };
}

const ROW_CLASS = 'pdk_dashboard-page__widgets-section__item__row';

// The language LuCI shows, not the browser's: a Russian interface with "04:59 PM" reads oddly
function uiLocale(): string | undefined {
  return (
    (typeof document !== 'undefined' && document.documentElement.lang) ||
    undefined
  );
}

// The time of a switch today, with the date for an earlier one
export function formatSince(since: number, now: Date = new Date()): string {
  if (!since) {
    return '';
  }

  const date = new Date(since * 1000);

  if (date.toDateString() === now.toDateString()) {
    return date.toLocaleTimeString(uiLocale(), {
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  return date.toLocaleString(uiLocale(), {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

// "since %s" is left out while the guard has not recorded the time of the switch
function withSince(text: string, since: number, now: Date) {
  const time = formatSince(since, now);
  return time ? `${text} ${_('since %s').replace('%s', time)}` : text;
}

export function getDnsGuardRow(
  status: Okop.GetDnsGuardStatus,
  now: Date = new Date(),
): DnsGuardRow {
  const key = _('DNS guard');
  const manageDnsmasq = Boolean(status.manage_dnsmasq);

  switch (status.state) {
    case 'ok':
      return {
        key,
        value: _('✔ Working'),
        hint: manageDnsmasq
          ? undefined
          : _('dnsmasq is not switched: "Dont Touch My DHCP!" is on'),
        attributes: { class: `${ROW_CLASS}--success` },
      };
    case 'sing_box_down':
      return {
        key,
        value: withSince(_('⚠ sing-box is not responding'), status.since, now),
        hint: manageDnsmasq
          ? _('DNS and traffic to the lists go directly')
          : _('Traffic to the lists goes directly'),
        attributes: { class: `${ROW_CLASS}--warning` },
      };
    case 'dns_server_down':
      return {
        key,
        value: withSince(
          _('⚠ sing-box DNS server is unreachable'),
          status.since,
          now,
        ),
        hint: _(
          'DNS goes through the regular servers, domains from the lists go directly',
        ),
        attributes: { class: `${ROW_CLASS}--warning` },
      };
    default:
      return {
        key,
        value: _('✘ Not running'),
        attributes: { class: `${ROW_CLASS}--error` },
      };
  }
}
