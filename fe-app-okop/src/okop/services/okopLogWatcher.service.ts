import { logger } from './logger.service';

export type LogFetcher = () => Promise<string> | string;

export interface OkopLogWatcherOptions {
  intervalMs?: number;
  onNewLog?: (line: string) => void;
}

export class OkopLogWatcher {
  private static instance: OkopLogWatcher;
  private fetcher?: LogFetcher;
  private onNewLog?: (line: string) => void;
  private intervalMs = 5000;
  private lastLines = new Set<string>();
  private primed = false;
  private timer?: ReturnType<typeof setInterval>;
  private running = false;
  private paused = false;

  private constructor() {
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) this.pause();
        else this.resume();
      });
    }
  }

  static getInstance(): OkopLogWatcher {
    if (!OkopLogWatcher.instance) {
      OkopLogWatcher.instance = new OkopLogWatcher();
    }
    return OkopLogWatcher.instance;
  }

  init(fetcher: LogFetcher, options?: OkopLogWatcherOptions): void {
    this.fetcher = fetcher;
    this.onNewLog = options?.onNewLog;
    this.intervalMs = options?.intervalMs ?? 5000;
    logger.info(
      '[OkopLogWatcher]',
      `initialized (interval: ${this.intervalMs}ms)`,
    );
  }

  async checkOnce(): Promise<void> {
    if (!this.fetcher) {
      logger.warn('[OkopLogWatcher]', 'fetcher not found');
      return;
    }

    if (this.paused) {
      logger.debug('[OkopLogWatcher]', 'skipped check — tab not visible');
      return;
    }

    try {
      const raw = await this.fetcher();
      const lines = raw.split('\n').filter(Boolean);

      // The fetcher returns everything since okop started, so a line is new when the previous fetch
      // did not have it. The first fetch only remembers: errors logged before the page was opened
      // were shown again on every page load, and a trimmed history brought old ones back.
      if (this.primed) {
        for (const line of lines) {
          if (!this.lastLines.has(line)) {
            this.onNewLog?.(line);
          }
        }
      }

      this.lastLines = new Set(lines);
      this.primed = true;
    } catch (err) {
      logger.error('[OkopLogWatcher]', 'failed to read logs:', err);
    }
  }

  start(): void {
    if (this.running) return;
    if (!this.fetcher) {
      logger.warn('[OkopLogWatcher]', 'attempted to start without fetcher');
      return;
    }

    this.running = true;
    // Remembers what is already in the log right away, so that the first interval only reports new lines
    this.checkOnce();
    this.timer = setInterval(() => this.checkOnce(), this.intervalMs);
    logger.info(
      '[OkopLogWatcher]',
      `started (interval: ${this.intervalMs}ms)`,
    );
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;
    if (this.timer) clearInterval(this.timer);
    logger.info('[OkopLogWatcher]', 'stopped');
  }

  pause(): void {
    if (!this.running || this.paused) return;
    this.paused = true;
    logger.info('[OkopLogWatcher]', 'paused (tab not visible)');
  }

  resume(): void {
    if (!this.running || !this.paused) return;
    this.paused = false;
    logger.info('[OkopLogWatcher]', 'resumed (tab active)');
    this.checkOnce(); // сразу проверить, не появились ли новые логи
  }

  reset(): void {
    this.lastLines.clear();
    this.primed = false;
    logger.info('[OkopLogWatcher]', 'log history reset');
  }
}
