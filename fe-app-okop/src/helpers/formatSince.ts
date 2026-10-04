// The language LuCI shows, not the browser's: a Russian interface with "04:59 PM" reads oddly
function uiLocale(): string | undefined {
  const lang =
    typeof document !== 'undefined' ? document.documentElement.lang : '';
  return lang ? lang.replace(/_/g, '-') : undefined;
}

// The time of a switch today, with the date for an earlier one
export function formatSince(since: number, now: Date = new Date()): string {
  if (!since) {
    return '';
  }

  const date = new Date(since * 1000);
  const today = date.toDateString() === now.toDateString();
  const options: Intl.DateTimeFormatOptions = today
    ? { hour: '2-digit', minute: '2-digit' }
    : { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' };

  // A language tag the browser does not accept would throw and stop the widget from rendering
  try {
    return date.toLocaleString(uiLocale(), options);
  } catch {
    return date.toLocaleString(undefined, options);
  }
}
