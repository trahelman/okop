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
