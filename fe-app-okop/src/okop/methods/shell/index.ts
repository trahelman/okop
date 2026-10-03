import { callBaseMethod } from './callBaseMethod';
import { ClashAPI, Okop } from '../../types';

export const OkopShellMethods = {
  checkDNSAvailable: async () =>
    callBaseMethod<Okop.DnsCheckResult>(
      Okop.AvailableMethods.CHECK_DNS_AVAILABLE,
    ),
  checkFakeIP: async () =>
    callBaseMethod<Okop.FakeIPCheckResult>(
      Okop.AvailableMethods.CHECK_FAKEIP,
    ),
  checkNftRules: async () =>
    callBaseMethod<Okop.NftRulesCheckResult>(
      Okop.AvailableMethods.CHECK_NFT_RULES,
    ),
  getStatus: async () =>
    callBaseMethod<Okop.GetStatus>(Okop.AvailableMethods.GET_STATUS),
  checkSingBox: async () =>
    callBaseMethod<Okop.SingBoxCheckResult>(
      Okop.AvailableMethods.CHECK_SING_BOX,
    ),
  getSingBoxStatus: async () =>
    callBaseMethod<Okop.GetSingBoxStatus>(
      Okop.AvailableMethods.GET_SING_BOX_STATUS,
    ),
  getDnsGuardStatus: async () =>
    callBaseMethod<Okop.GetDnsGuardStatus>(
      Okop.AvailableMethods.GET_DNS_GUARD_STATUS,
    ),
  getClashApiProxies: async () =>
    callBaseMethod<ClashAPI.Proxies>(Okop.AvailableMethods.CLASH_API, [
      Okop.AvailableClashAPIMethods.GET_PROXIES,
    ]),
  getClashApiProxyLatency: async (tag: string) =>
    callBaseMethod<Okop.GetClashApiProxyLatency>(
      Okop.AvailableMethods.CLASH_API,
      [Okop.AvailableClashAPIMethods.GET_PROXY_LATENCY, tag, '5000'],
    ),
  getClashApiGroupLatency: async (tag: string) =>
    callBaseMethod<Okop.GetClashApiGroupLatency>(
      Okop.AvailableMethods.CLASH_API,
      [Okop.AvailableClashAPIMethods.GET_GROUP_LATENCY, tag, '10000'],
    ),
  setClashApiGroupProxy: async (group: string, proxy: string) =>
    callBaseMethod<unknown>(Okop.AvailableMethods.CLASH_API, [
      Okop.AvailableClashAPIMethods.SET_GROUP_PROXY,
      group,
      proxy,
    ]),
  restart: async () =>
    callBaseMethod<unknown>(
      Okop.AvailableMethods.RESTART,
      [],
      '/etc/init.d/okop',
    ),
  start: async () =>
    callBaseMethod<unknown>(
      Okop.AvailableMethods.START,
      [],
      '/etc/init.d/okop',
    ),
  stop: async () =>
    callBaseMethod<unknown>(
      Okop.AvailableMethods.STOP,
      [],
      '/etc/init.d/okop',
    ),
  enable: async () =>
    callBaseMethod<unknown>(
      Okop.AvailableMethods.ENABLE,
      [],
      '/etc/init.d/okop',
    ),
  disable: async () =>
    callBaseMethod<unknown>(
      Okop.AvailableMethods.DISABLE,
      [],
      '/etc/init.d/okop',
    ),
  globalCheck: async () =>
    callBaseMethod<unknown>(Okop.AvailableMethods.GLOBAL_CHECK),
  showSingBoxConfig: async () =>
    callBaseMethod<unknown>(Okop.AvailableMethods.SHOW_SING_BOX_CONFIG),
  checkLogs: async () =>
    callBaseMethod<unknown>(Okop.AvailableMethods.CHECK_LOGS),
  getSystemInfo: async () =>
    callBaseMethod<Okop.GetSystemInfo>(
      Okop.AvailableMethods.GET_SYSTEM_INFO,
    ),
};
