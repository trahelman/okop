import {
  getClashWsUrl,
  onMount,
  preserveScrollForPage,
} from '../../../helpers';
import { prettyBytes } from '../../../helpers/prettyBytes';
import { CustomOkopMethods, OkopShellMethods } from '../../methods';
import { logger, socket, store, StoreType } from '../../services';
import { renderSections, renderWidget } from './partials';
import { fetchServicesInfo } from '../../fetchers';
import { getClashApiSecret } from '../../methods/custom/getClashApiSecret';
import { markUnreachable } from './markUnreachable';
import { getDnsGuardRow } from './getDnsGuardRow';
import { getListUpdateRow } from './getListUpdateRow';
import { Okop } from '../../types';

// Latency is tested when the dashboard opens and then periodically: nothing else tests a connection a
// section uses directly, and its card kept the last result after the connection went down.
const LATENCY_TEST_INTERVAL = 60_000;
// Each refresh runs four okop commands on the router, so not more often than this
const SERVICES_INFO_INTERVAL = 30_000;

// Outbounds whose last latency test on this page failed. Only a test that ran counts: sing-box also
// has no latency for an outbound nobody tested since it restarted.
const unreachableOutbounds = new Set<string>();
let latencyTestTimer: ReturnType<typeof setInterval> | undefined;
let servicesInfoTimer: ReturnType<typeof setInterval> | undefined;
// LuCI calls initController on load, render and save, and the tab listener mounts too, so mounts
// overlap. Each one bumps the generation; work of an older one stops at its next await.
let mountGeneration = 0;
// Results of fetches started earlier than the last applied one are dropped
let sectionsRequest = 0;

// Fetchers

async function fetchDashboardSections() {
  const prev = store.get().sectionsWidget;
  const request = ++sectionsRequest;

  store.set({
    sectionsWidget: {
      ...prev,
      failed: false,
    },
  });

  const { data, success } = await CustomOkopMethods.getDashboardSections();

  if (request !== sectionsRequest) {
    return;
  }

  if (!success) {
    logger.error('[DASHBOARD]', 'fetchDashboardSections: failed to fetch');
  }

  store.set({
    sectionsWidget: {
      // A test may still be running, it clears the flag itself
      latencyFetching: store.get().sectionsWidget.latencyFetching,
      loading: false,
      failed: !success,
      data: markUnreachable(data, unreachableOutbounds),
    },
  });
}

function recordLatencyResult(code: string, responded: boolean) {
  if (responded) {
    unreachableOutbounds.delete(code);
  } else {
    unreachableOutbounds.add(code);
  }
}

// A call that did not run (rpc error, timeout, Clash API down) changes nothing
async function testSectionLatency(section: Okop.OutboundGroup) {
  if (section.withTagSelect) {
    const result = await OkopShellMethods.getClashApiGroupLatency(section.code);
    if (!result.success || typeof result.data !== 'object' || !result.data) {
      return;
    }

    // The group test lists only the members that responded
    const delays = result.data;
    section.outbounds.forEach((outbound) =>
      recordLatencyResult(outbound.code, Number(delays[outbound.code]) > 0),
    );
    return;
  }

  const outbound = section.outbounds[0];
  if (!outbound) {
    return;
  }

  const result = await OkopShellMethods.getClashApiProxyLatency(outbound.code);
  if (!result.success || typeof result.data !== 'object' || !result.data) {
    return;
  }

  recordLatencyResult(outbound.code, Number(result.data.delay) > 0);
}

function setLatencyFetching(latencyFetching: boolean) {
  store.set({
    sectionsWidget: {
      ...store.get().sectionsWidget,
      latencyFetching,
    },
  });
}

async function connectToClashSockets() {
  const clashApiSecret = await getClashApiSecret();

  socket.subscribe(
    `${getClashWsUrl()}/traffic?token=${encodeURIComponent(clashApiSecret)}`,
    (msg) => {
      const parsedMsg = JSON.parse(msg);

      store.set({
        bandwidthWidget: {
          loading: false,
          failed: false,
          data: { up: parsedMsg.up, down: parsedMsg.down },
        },
      });
    },
    (_err) => {
      logger.error(
        '[DASHBOARD]',
        'connectToClashSockets - traffic: failed to connect to',
        getClashWsUrl(),
      );
      store.set({
        bandwidthWidget: {
          loading: false,
          failed: true,
          data: { up: 0, down: 0 },
        },
      });
    },
  );

  socket.subscribe(
    `${getClashWsUrl()}/connections?token=${encodeURIComponent(clashApiSecret)}`,
    (msg) => {
      const parsedMsg = JSON.parse(msg);

      store.set({
        trafficTotalWidget: {
          loading: false,
          failed: false,
          data: {
            downloadTotal: parsedMsg.downloadTotal,
            uploadTotal: parsedMsg.uploadTotal,
          },
        },
        systemInfoWidget: {
          loading: false,
          failed: false,
          data: {
            connections: parsedMsg.connections?.length,
            memory: parsedMsg.memory,
          },
        },
      });
    },
    (_err) => {
      logger.error(
        '[DASHBOARD]',
        'connectToClashSockets - connections: failed to connect to',
        getClashWsUrl(),
      );
      store.set({
        trafficTotalWidget: {
          loading: false,
          failed: true,
          data: { downloadTotal: 0, uploadTotal: 0 },
        },
        systemInfoWidget: {
          loading: false,
          failed: true,
          data: {
            connections: 0,
            memory: 0,
          },
        },
      });
    },
  );
}

// Handlers

async function handleChooseOutbound(selector: string, tag: string) {
  await OkopShellMethods.setClashApiGroupProxy(selector, tag);
  await fetchDashboardSections();
}

async function handleTestLatency(section: Okop.OutboundGroup) {
  const generation = mountGeneration;
  setLatencyFetching(true);

  try {
    await testSectionLatency(section);
    if (generation === mountGeneration) {
      await fetchDashboardSections();
    }
  } finally {
    if (generation === mountGeneration) {
      setLatencyFetching(false);
    }
  }
}

async function testAllLatency(showProgress: boolean) {
  const generation = mountGeneration;
  const sections = store.get().sectionsWidget.data;

  if (showProgress) {
    setLatencyFetching(true);
  }

  try {
    await Promise.all(sections.map((section) => testSectionLatency(section)));
    if (generation === mountGeneration) {
      await fetchDashboardSections();
    }
  } finally {
    if (showProgress && generation === mountGeneration) {
      setLatencyFetching(false);
    }
  }
}

// A browser tab in the background does not need fresh numbers, the router does the work for nothing
function whileVisible(callback: () => void) {
  return () => {
    if (!document.hidden) {
      callback();
    }
  };
}

// Renderer

async function renderSectionsWidget() {
  logger.debug('[DASHBOARD]', 'renderSectionsWidget');
  const sectionsWidget = store.get().sectionsWidget;
  const container = document.getElementById('dashboard-sections-grid');

  if (sectionsWidget.loading || sectionsWidget.failed) {
    const renderedWidget = renderSections({
      loading: sectionsWidget.loading,
      failed: sectionsWidget.failed,
      section: {
        code: '',
        displayName: '',
        outbounds: [],
        withTagSelect: false,
      },
      onTestLatency: () => {},
      onChooseOutbound: () => {},
      latencyFetching: sectionsWidget.latencyFetching,
    });

    return preserveScrollForPage(() => {
      container!.replaceChildren(renderedWidget);
    });
  }

  const renderedWidgets = sectionsWidget.data.map((section) =>
    renderSections({
      loading: sectionsWidget.loading,
      failed: sectionsWidget.failed,
      section,
      latencyFetching: sectionsWidget.latencyFetching,
      onTestLatency: () => handleTestLatency(section),
      onChooseOutbound: (selector, tag) => {
        handleChooseOutbound(selector, tag);
      },
    }),
  );

  return preserveScrollForPage(() => {
    container!.replaceChildren(...renderedWidgets);
  });
}

async function renderBandwidthWidget() {
  logger.debug('[DASHBOARD]', 'renderBandwidthWidget');
  const traffic = store.get().bandwidthWidget;

  const container = document.getElementById('dashboard-widget-traffic');

  if (traffic.loading || traffic.failed) {
    const renderedWidget = renderWidget({
      loading: traffic.loading,
      failed: traffic.failed,
      title: '',
      items: [],
    });

    return container!.replaceChildren(renderedWidget);
  }

  const renderedWidget = renderWidget({
    loading: traffic.loading,
    failed: traffic.failed,
    title: _('Traffic'),
    items: [
      { key: _('Uplink'), value: `${prettyBytes(traffic.data.up)}/s` },
      { key: _('Downlink'), value: `${prettyBytes(traffic.data.down)}/s` },
    ],
  });

  container!.replaceChildren(renderedWidget);
}

async function renderTrafficTotalWidget() {
  logger.debug('[DASHBOARD]', 'renderTrafficTotalWidget');
  const trafficTotalWidget = store.get().trafficTotalWidget;

  const container = document.getElementById('dashboard-widget-traffic-total');

  if (trafficTotalWidget.loading || trafficTotalWidget.failed) {
    const renderedWidget = renderWidget({
      loading: trafficTotalWidget.loading,
      failed: trafficTotalWidget.failed,
      title: '',
      items: [],
    });

    return container!.replaceChildren(renderedWidget);
  }

  const renderedWidget = renderWidget({
    loading: trafficTotalWidget.loading,
    failed: trafficTotalWidget.failed,
    title: _('Traffic Total'),
    items: [
      {
        key: _('Uplink'),
        value: String(prettyBytes(trafficTotalWidget.data.uploadTotal)),
      },
      {
        key: _('Downlink'),
        value: String(prettyBytes(trafficTotalWidget.data.downloadTotal)),
      },
    ],
  });

  container!.replaceChildren(renderedWidget);
}

async function renderSystemInfoWidget() {
  logger.debug('[DASHBOARD]', 'renderSystemInfoWidget');
  const systemInfoWidget = store.get().systemInfoWidget;

  const container = document.getElementById('dashboard-widget-system-info');

  if (systemInfoWidget.loading || systemInfoWidget.failed) {
    const renderedWidget = renderWidget({
      loading: systemInfoWidget.loading,
      failed: systemInfoWidget.failed,
      title: '',
      items: [],
    });

    return container!.replaceChildren(renderedWidget);
  }

  const renderedWidget = renderWidget({
    loading: systemInfoWidget.loading,
    failed: systemInfoWidget.failed,
    title: _('System info'),
    items: [
      {
        key: _('Active Connections'),
        value: String(systemInfoWidget.data.connections),
      },
      {
        key: _('Memory Usage'),
        value: String(prettyBytes(systemInfoWidget.data.memory)),
      },
    ],
  });

  container!.replaceChildren(renderedWidget);
}

async function renderServicesInfoWidget() {
  logger.debug('[DASHBOARD]', 'renderServicesInfoWidget');
  const servicesInfoWidget = store.get().servicesInfoWidget;

  const container = document.getElementById('dashboard-widget-service-info');

  if (servicesInfoWidget.loading || servicesInfoWidget.failed) {
    const renderedWidget = renderWidget({
      loading: servicesInfoWidget.loading,
      failed: servicesInfoWidget.failed,
      title: '',
      items: [],
    });

    return container!.replaceChildren(renderedWidget);
  }

  const renderedWidget = renderWidget({
    loading: servicesInfoWidget.loading,
    failed: servicesInfoWidget.failed,
    title: _('Services info'),
    items: [
      {
        key: _('Okop'),
        value: servicesInfoWidget.data.okop ? _('✔ Enabled') : _('✘ Disabled'),
        attributes: {
          class: servicesInfoWidget.data.okop
            ? 'pdk_dashboard-page__widgets-section__item__row--success'
            : 'pdk_dashboard-page__widgets-section__item__row--error',
        },
      },
      {
        key: _('Sing-box'),
        value: servicesInfoWidget.data.singbox
          ? _('✔ Running')
          : _('✘ Stopped'),
        attributes: {
          class: servicesInfoWidget.data.singbox
            ? 'pdk_dashboard-page__widgets-section__item__row--success'
            : 'pdk_dashboard-page__widgets-section__item__row--error',
        },
      },
      ...(servicesInfoWidget.data.dnsGuard
        ? [getDnsGuardRow(servicesInfoWidget.data.dnsGuard)]
        : []),
      ...(servicesInfoWidget.data.listUpdate
        ? [getListUpdateRow(servicesInfoWidget.data.listUpdate)]
        : []),
    ],
  });

  container!.replaceChildren(renderedWidget);
}

async function onStoreUpdate(
  next: StoreType,
  prev: StoreType,
  diff: Partial<StoreType>,
) {
  if (diff.sectionsWidget) {
    renderSectionsWidget();
  }

  if (diff.bandwidthWidget) {
    renderBandwidthWidget();
  }

  if (diff.trafficTotalWidget) {
    renderTrafficTotalWidget();
  }

  if (diff.systemInfoWidget) {
    renderSystemInfoWidget();
  }

  if (diff.servicesInfoWidget) {
    renderServicesInfoWidget();
  }
}

async function onPageMount() {
  // Cleanup before mount
  onPageUnmount();
  const generation = mountGeneration;

  // Add new listener
  store.subscribe(onStoreUpdate);

  // Initial sections fetch
  await fetchDashboardSections();
  if (generation !== mountGeneration) {
    return;
  }

  latencyTestTimer = setInterval(
    whileVisible(() => testAllLatency(false)),
    LATENCY_TEST_INTERVAL,
  );
  servicesInfoTimer = setInterval(
    whileVisible(() => fetchServicesInfo()),
    SERVICES_INFO_INTERVAL,
  );
  testAllLatency(true);

  await fetchServicesInfo();
  if (generation !== mountGeneration) {
    return;
  }

  await connectToClashSockets();
}

function onPageUnmount() {
  mountGeneration++;
  // Remove old listener
  store.unsubscribe(onStoreUpdate);
  clearInterval(latencyTestTimer);
  latencyTestTimer = undefined;
  clearInterval(servicesInfoTimer);
  servicesInfoTimer = undefined;
  unreachableOutbounds.clear();
  // Clear store
  store.reset([
    'bandwidthWidget',
    'trafficTotalWidget',
    'systemInfoWidget',
    'servicesInfoWidget',
    'sectionsWidget',
  ]);
  socket.resetAll();
}

function registerLifecycleListeners() {
  store.subscribe((next, prev, diff) => {
    if (
      diff.tabService &&
      next.tabService.current !== prev.tabService.current
    ) {
      logger.debug(
        '[DASHBOARD]',
        'active tab diff event, active tab:',
        diff.tabService.current,
      );
      const isDashboardVisible = next.tabService.current === 'dashboard';

      if (isDashboardVisible) {
        logger.debug(
          '[DASHBOARD]',
          'registerLifecycleListeners',
          'onPageMount',
        );
        return onPageMount();
      }

      if (!isDashboardVisible) {
        logger.debug(
          '[DASHBOARD]',
          'registerLifecycleListeners',
          'onPageUnmount',
        );
        return onPageUnmount();
      }
    }
  });
}

// LuCI calls cfgvalue, and with it initController, on load, on render and on every save. Each call used
// to add a DOM observer and a store listener that were never removed.
let mountPending = false;
let lifecycleListenersRegistered = false;

export async function initController(): Promise<void> {
  if (mountPending) {
    return;
  }

  mountPending = true;
  onMount('dashboard-status').then(() => {
    mountPending = false;
    logger.debug('[DASHBOARD]', 'initController', 'onMount');
    onPageMount();

    if (!lifecycleListenersRegistered) {
      lifecycleListenersRegistered = true;
      registerLifecycleListeners();
    }
  });
}
