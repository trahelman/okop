import { describe, expect, it } from 'vitest';
import {
  getListName,
  getListUpdateResultMessage,
  getListUpdateRow,
} from '../getListUpdateRow';
import { formatSince } from '../../../../helpers/formatSince';
import { Okop } from '../../../types';

const NOW = new Date(2026, 9, 4, 9, 30);
const FINISHED = Math.floor(new Date(2026, 9, 4, 4, 0).getTime() / 1000);

function status(
  patch: Partial<Okop.GetListUpdateStatus>,
): Okop.GetListUpdateStatus {
  return {
    state: 'ok',
    started: FINISHED - 20,
    finished: FINISHED,
    reason: '',
    failed: [],
    ...patch,
  };
}

describe('getListName', () => {
  it('takes the file name of the URL', () => {
    expect(
      getListName(
        'https://github.com/itdoginfo/allow-domains/releases/latest/download/youtube.srs',
      ),
    ).toBe('youtube.srs');
  });

  it('drops the query and decodes the name', () => {
    expect(getListName('https://example.com/my%20list.lst?token=1')).toBe(
      'my list.lst',
    );
  });

  it('keeps a URL without a path', () => {
    expect(getListName('https://example.com/')).toBe('example.com');
  });
});

describe('getListUpdateRow', () => {
  it('shows a successful update with its time', () => {
    const row = getListUpdateRow(status({}), NOW);

    expect(row.value).toBe(`✔ Updated: ${formatSince(FINISHED, NOW)}`);
    expect(row.attributes.class).toContain('--success');
  });

  it('counts and names the lists that failed', () => {
    const row = getListUpdateRow(
      status({
        state: 'partial',
        failed: [
          'https://example.com/a.lst',
          'https://example.com/rules/b.srs',
        ],
      }),
      NOW,
    );

    expect(row.value).toBe(
      `⚠ Not downloaded: 2 (${formatSince(FINISHED, NOW)})`,
    );
    expect(row.hint).toBe('a.lst, b.srs. Lists downloaded before keep working');
    expect(row.attributes.class).toContain('--warning');
  });

  it('says why an update without network did not run', () => {
    const row = getListUpdateRow(
      status({ state: 'network', reason: 'github' }),
      NOW,
    );

    expect(row.hint).toBe(
      'GitHub is unreachable. Lists downloaded before keep working',
    );
  });

  it('shows a running update without a time', () => {
    const row = getListUpdateRow(
      status({ state: 'running', finished: 0 }),
      NOW,
    );

    expect(row.value).toBe('Updating…');
  });
});

describe('getListUpdateResultMessage', () => {
  it('reports success', () => {
    expect(getListUpdateResultMessage(status({}))).toEqual({
      message: 'Lists updated',
      type: 'success',
    });
  });

  it('names the lists that failed', () => {
    expect(
      getListUpdateResultMessage(
        status({ state: 'partial', failed: ['https://example.com/a.lst'] }),
      ),
    ).toEqual({ message: 'Not downloaded: a.lst', type: 'error' });
  });

  it('reports missing DNS', () => {
    expect(
      getListUpdateResultMessage(status({ state: 'network', reason: 'dns' })),
    ).toEqual({
      message: 'Lists were not updated: DNS does not work',
      type: 'error',
    });
  });
});
