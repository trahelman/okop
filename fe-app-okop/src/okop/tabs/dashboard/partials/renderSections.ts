import { Okop } from '../../../types';

interface IRenderSectionsProps {
  loading: boolean;
  failed: boolean;
  section: Okop.OutboundGroup;
  onTestLatency: () => void;
  onChooseOutbound: (selector: string, tag: string) => void;
  latencyFetching: boolean;
}

function renderFailedState() {
  return E(
    'div',
    {
      class: 'pdk_dashboard-page__outbound-section centered',
      style: 'height: 127px',
    },
    E('span', {}, [E('span', {}, _('Dashboard currently unavailable'))]),
  );
}

function renderLoadingState() {
  return E('div', {
    id: 'dashboard-sections-grid-skeleton',
    class: 'pdk_dashboard-page__outbound-section skeleton',
    style: 'height: 127px',
  });
}

export function renderDefaultState({
  section,
  onChooseOutbound,
  onTestLatency,
  latencyFetching,
}: IRenderSectionsProps) {
  // A fallback group switches by itself, its members are only shown
  const selectable = section.selectable ?? section.withTagSelect;

  function renderOutbound(outbound: Okop.Outbound) {
    function getLatencyClass() {
      if (outbound.unreachable) {
        return 'pdk_dashboard-page__outbound-grid__item__latency--red';
      }

      if (!outbound.latency) {
        return 'pdk_dashboard-page__outbound-grid__item__latency--empty';
      }

      if (outbound.latency < 800) {
        return 'pdk_dashboard-page__outbound-grid__item__latency--green';
      }

      if (outbound.latency < 1500) {
        return 'pdk_dashboard-page__outbound-grid__item__latency--yellow';
      }

      return 'pdk_dashboard-page__outbound-grid__item__latency--red';
    }

    function getStateClass() {
      if (!outbound.selected) {
        return '';
      }

      return outbound.unreachable
        ? 'pdk_dashboard-page__outbound-grid__item--unreachable'
        : 'pdk_dashboard-page__outbound-grid__item--active';
    }

    function getLatencyText() {
      if (outbound.unreachable) {
        return _('Unreachable');
      }

      return outbound.latency ? `${outbound.latency}ms` : 'N/A';
    }

    return E(
      'div',
      {
        class: `pdk_dashboard-page__outbound-grid__item ${getStateClass()} ${selectable ? 'pdk_dashboard-page__outbound-grid__item--selectable' : ''}`,
        click: () =>
          selectable && onChooseOutbound(section.code, outbound.code),
      },
      [
        E('b', {}, [outbound.displayName]),
        E('div', { class: 'pdk_dashboard-page__outbound-grid__item__footer' }, [
          E('div', { class: 'pdk_dashboard-page__outbound-grid__item__type' }, [
            outbound.type,
          ]),
          E('div', { class: getLatencyClass() }, getLatencyText()),
        ]),
      ],
    );
  }

  return E('div', { class: 'pdk_dashboard-page__outbound-section' }, [
    // Title with test latency
    E('div', { class: 'pdk_dashboard-page__outbound-section__title-section' }, [
      E(
        'div',
        {
          class: 'pdk_dashboard-page__outbound-section__title-section__title',
        },
        section.displayName,
      ),
      latencyFetching
        ? E('div', { class: 'skeleton', style: 'width: 99px; height: 28px' })
        : E(
            'button',
            {
              class: 'btn dashboard-sections-grid-item-test-latency',
              click: () => onTestLatency(),
            },
            _('Test latency'),
          ),
    ]),
    E(
      'div',
      { class: 'pdk_dashboard-page__outbound-grid' },
      section.outbounds.map((outbound) => renderOutbound(outbound)),
    ),
  ]);
}

export function renderSections(props: IRenderSectionsProps) {
  if (props.failed) {
    return renderFailedState();
  }

  if (props.loading) {
    return renderLoadingState();
  }

  return renderDefaultState(props);
}
