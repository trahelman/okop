import { describe, it, expect } from 'vitest';
import { OkopLogWatcher } from '../okopLogWatcher.service';

function watcherWith(outputs) {
  const watcher = OkopLogWatcher.getInstance();
  const reported = [];
  let call = 0;
  watcher.reset();
  watcher.init(() => outputs[Math.min(call++, outputs.length - 1)], {
    onNewLog: (line) => reported.push(line),
  });
  return { watcher, reported };
}

describe('OkopLogWatcher', () => {
  it('does not report lines logged before the first check', async () => {
    const { watcher, reported } = watcherWith(['old error\n', 'old error\n']);
    await watcher.checkOnce();
    await watcher.checkOnce();
    expect(reported).toEqual([]);
  });

  it('reports lines that appear after the first check, once', async () => {
    const { watcher, reported } = watcherWith([
      'a\n',
      'a\nb\n',
      'a\nb\n',
      'a\nb\nc\n',
    ]);
    for (let i = 0; i < 4; i++) await watcher.checkOnce();
    expect(reported).toEqual(['b', 'c']);
  });

  it('does not bring back old lines of a long log', async () => {
    const long = Array.from({ length: 800 }, (_, i) => `line ${i}`).join('\n');
    const { watcher, reported } = watcherWith([long, long, `${long}\nnew`]);
    for (let i = 0; i < 3; i++) await watcher.checkOnce();
    expect(reported).toEqual(['new']);
  });
});
