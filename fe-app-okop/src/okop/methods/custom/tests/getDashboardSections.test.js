import { describe, it, expect, vi, beforeEach } from 'vitest';

const config = vi.hoisted(() => ({ sections: [], proxies: {} }));

vi.mock('../getConfigSections', () => ({
  getConfigSections: async () => config.sections,
}));
vi.mock('../../shell', () => ({
  OkopShellMethods: {
    getClashApiProxies: async () => ({
      success: true,
      data: { proxies: config.proxies },
    }),
  },
}));

import { getDashboardSections } from '../getDashboardSections';

const proxy = (type, extra = {}) => ({ type, history: [{ delay: 100 }], ...extra });

beforeEach(() => {
  config.sections = [
    { '.name': 'settings', '.type': 'settings' },
    { '.name': 'main', '.type': 'section', connection_type: 'outbound', outbound: 'fb' },
    { '.name': 'blk', '.type': 'section', connection_type: 'block' },
    { '.name': 'vpn', '.type': 'outbound', type: 'interface', interface: 'wg0' },
    { '.name': 'nl', '.type': 'outbound', type: 'url', url: 'vless://u@h:443?type=tcp#Amsterdam' },
    { '.name': 'fb', '.type': 'outbound', type: 'fallback', members: ['vpn', 'nl'] },
    { '.name': 'spare', '.type': 'outbound', type: 'url', url: 'ss://x@h:1#Spare' },
  ];
  config.proxies = {
    'vpn-out': proxy('Direct'),
    'nl-out': proxy('VLESS'),
    'fb-out': proxy('Selector', { now: 'nl-out', all: ['vpn-out', 'nl-out'] }),
    'spare-out': proxy('Shadowsocks'),
  };
});

describe('getDashboardSections', () => {
  it('shows connections used by sections and unused ones, not group members', async () => {
    const { data } = await getDashboardSections();
    expect(data.map((group) => group.displayName)).toEqual(['fb', 'spare']);
  });

  it('shows the members of a fallback group, which cannot be chosen by hand', async () => {
    const { data } = await getDashboardSections();
    const fallback = data.find((group) => group.code === 'fb-out');
    expect(fallback.withTagSelect).toBe(true);
    expect(fallback.selectable).toBe(false);
    expect(fallback.outbounds.map((member) => [member.displayName, member.selected])).toEqual([
      ['vpn · wg0', false],
      ['nl · Amsterdam', true],
    ]);
  });

  it('names a single connection after its link', async () => {
    const { data } = await getDashboardSections();
    expect(data.find((group) => group.code === 'spare-out').outbounds[0].displayName).toBe('Spare');
  });

  it('offers the fastest member and the members of a URLTest group to choose', async () => {
    config.sections[5] = { '.name': 'fb', '.type': 'outbound', type: 'urltest', members: ['vpn', 'nl'] };
    config.proxies['fb-out'].now = 'fb-urltest-out';
    config.proxies['fb-urltest-out'] = proxy('URLTest');
    const { data } = await getDashboardSections();
    const urltest = data.find((group) => group.code === 'fb-out');
    expect(urltest.selectable).toBe(true);
    expect(urltest.outbounds.map((member) => [member.code, member.selected])).toEqual([
      ['fb-urltest-out', true],
      ['vpn-out', false],
      ['nl-out', false],
    ]);
  });
});
