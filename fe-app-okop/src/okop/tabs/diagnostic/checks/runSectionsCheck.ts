import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { OkopShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';
import { getMeta } from '../helpers/getMeta';
import { getDashboardSections } from '../../../methods/custom/getDashboardSections';
import { IDiagnosticsChecksItem } from '../../../services';

export async function runSectionsCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.OUTBOUNDS;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const sections = await getDashboardSections();

  if (!sections.success) {
    updateCheckStore({
      order,
      code,
      title,
      description: _('Cannot receive checks result'),
      state: 'error',
      items: [],
    });

    throw new Error('Sections checks failed');
  }

  const items = (await Promise.all(
    sections.data.map(async (section) => {
      async function getLatency() {
        if (section.withTagSelect) {
          const latencyGroup = await OkopShellMethods.getClashApiGroupLatency(
            section.code,
          );

          const selectedOutbound = section.outbounds.find(
            (item) => item.selected,
          );

          const isUrlTest = selectedOutbound?.type === 'URLTest';

          const success = latencyGroup.success && !latencyGroup.data.message;

          if (success) {
            if (isUrlTest) {
              const latency = Object.values(latencyGroup.data)
                .map((item) => (item ? `${item}ms` : 'n/a'))
                .join(' / ');

              return {
                success: true,
                latency: `[${_('Fastest')}] ${latency}`,
              };
            }

            let selectedProxyDelay =
              latencyGroup.data?.[selectedOutbound?.code ?? ''];

            // A group delay skips a member whose own member was already tested (a nested group):
            // the selected member is then tested on its own
            if (!selectedProxyDelay && selectedOutbound?.code) {
              const own = await OkopShellMethods.getClashApiProxyLatency(
                selectedOutbound.code,
              );
              if (own.success && !own.data.message) {
                selectedProxyDelay = own.data.delay;
              }
            }

            if (selectedProxyDelay) {
              return {
                success: true,
                latency: `[${selectedOutbound?.displayName ?? ''}] ${selectedProxyDelay}ms`,
              };
            }

            return {
              success: false,
              latency: `[${selectedOutbound?.displayName ?? ''}] ${_('Not responding')}`,
            };
          }

          return {
            success: false,
            latency: _('Not responding'),
          };
        }

        const latencyProxy = await OkopShellMethods.getClashApiProxyLatency(
          section.code,
        );

        const success = latencyProxy.success && !latencyProxy.data.message;

        if (success) {
          return {
            success: true,
            latency: `${latencyProxy.data.delay} ms`,
          };
        }

        return {
          success: false,
          latency: _('Not responding'),
        };
      }

      const { latency, success } = await getLatency();

      return {
        state: success ? 'success' : 'error',
        key: section.displayName,
        value: latency,
      };
    }),
  )) as Array<IDiagnosticsChecksItem>;

  const allGood = items.every((item) => item.state === 'success');

  const atLeastOneGood = items.some((item) => item.state === 'success');

  const { state, description } = getMeta({ atLeastOneGood, allGood });

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items,
  });

  if (!atLeastOneGood) {
    throw new Error('Sections checks failed');
  }
}
