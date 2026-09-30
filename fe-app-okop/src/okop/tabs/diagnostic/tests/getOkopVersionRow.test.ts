import { describe, expect, it } from 'vitest';
import { getOkopVersionRow } from '../helpers/getOkopVersionRow';
import type { StoreType } from '../../../services/store.service';

function makeDiagnosticsSystemInfo(
  patch: Partial<StoreType['diagnosticsSystemInfo']> = {},
): StoreType['diagnosticsSystemInfo'] {
  return {
    loading: false,
    okop_version: '1.2.3',
    okop_latest_version: '1.2.3',
    luci_app_version: '1.0.0',
    sing_box_version: '1.11.0',
    openwrt_version: 'OpenWrt 25.12',
    device_model: 'Test Router',
    ...patch,
  };
}

describe('getOkopVersionRow', () => {
  it('returns Latest when versions differ only by leading v', () => {
    const row = getOkopVersionRow(
      makeDiagnosticsSystemInfo({
        okop_version: 'v1.2.3',
        okop_latest_version: '1.2.3',
      }),
    );

    expect(row).toEqual({
      key: 'Okop',
      value: 'v1.2.3',
      tag: {
        label: 'Latest',
        kind: 'success',
      },
    });
  });

  it('returns Outdated when versions differ', () => {
    const row = getOkopVersionRow(
      makeDiagnosticsSystemInfo({
        okop_version: '1.2.2',
        okop_latest_version: '1.2.3',
      }),
    );

    expect(row).toEqual({
      key: 'Okop',
      value: '1.2.2',
      tag: {
        label: 'Outdated',
        kind: 'warning',
      },
    });
  });

  it('returns plain row without tag for dev build', () => {
    const row = getOkopVersionRow(
      makeDiagnosticsSystemInfo({
        okop_version: 'COMPILED_VERSION',
      }),
    );

    expect(row).toEqual({
      key: 'Okop',
      value: 'dev',
    });
  });
});
