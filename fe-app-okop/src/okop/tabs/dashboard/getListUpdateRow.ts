import { Okop } from '../../types';
import { formatSince } from '../../../helpers/formatSince';

export interface ListUpdateRow {
  key: string;
  value: string;
  hint?: string;
  attributes: { class: string };
}

const ROW_CLASS = 'pdk_dashboard-page__widgets-section__item__row';

// A list is named by its file: the whole URL does not fit into the widget
export function getListName(url: string): string {
  const path = url.split(/[?#]/)[0].replace(/\/+$/, '');
  const name = path.slice(path.lastIndexOf('/') + 1) || url;

  try {
    return decodeURIComponent(name);
  } catch {
    return name;
  }
}

function getFailedNames(status: Okop.GetListUpdateStatus): string {
  return status.failed.map(getListName).join(', ');
}

function getNetworkReason(status: Okop.GetListUpdateStatus): string {
  return status.reason === 'dns'
    ? _('DNS does not work')
    : _('GitHub is unreachable');
}

function withTime(text: string, time: number, now: Date) {
  const formatted = formatSince(time, now);
  return formatted ? `${text} (${formatted})` : text;
}

export function getListUpdateRow(
  status: Okop.GetListUpdateStatus,
  now: Date = new Date(),
): ListUpdateRow {
  const key = _('Lists');
  const previousCopies = _('Lists downloaded before keep working');

  switch (status.state) {
    case 'running':
      return { key, value: _('Updating…'), attributes: { class: '' } };
    case 'ok':
      return {
        key,
        value: _('✔ Updated: %s').replace(
          '%s',
          formatSince(status.finished, now),
        ),
        attributes: { class: `${ROW_CLASS}--success` },
      };
    case 'partial':
      return {
        key,
        value: withTime(
          status.failed.length
            ? _('⚠ Not downloaded: %s').replace(
                '%s',
                String(status.failed.length),
              )
            : _('⚠ Not all lists were updated'),
          status.finished,
          now,
        ),
        hint: status.failed.length
          ? `${getFailedNames(status)}. ${previousCopies}`
          : previousCopies,
        attributes: { class: `${ROW_CLASS}--warning` },
      };
    case 'network':
      return {
        key,
        value: withTime(_('⚠ Not updated'), status.finished, now),
        hint: `${getNetworkReason(status)}. ${previousCopies}`,
        attributes: { class: `${ROW_CLASS}--warning` },
      };
    case 'interrupted':
      return {
        key,
        value: withTime(_('⚠ Update interrupted'), status.started, now),
        hint: previousCopies,
        attributes: { class: `${ROW_CLASS}--warning` },
      };
    default:
      return { key, value: _('Not updated yet'), attributes: { class: '' } };
  }
}

// What the notification after the button says
export function getListUpdateResultMessage(status: Okop.GetListUpdateStatus): {
  message: string;
  type: 'success' | 'error';
} {
  switch (status.state) {
    case 'ok':
      return { message: _('Lists updated'), type: 'success' };
    case 'partial':
      return {
        message: status.failed.length
          ? _('Not downloaded: %s').replace('%s', getFailedNames(status))
          : _('Not all lists were updated'),
        type: 'error',
      };
    case 'network':
      return {
        message: _('Lists were not updated: %s').replace(
          '%s',
          getNetworkReason(status),
        ),
        type: 'error',
      };
    case 'interrupted':
      return { message: _('The lists update was interrupted'), type: 'error' };
    default:
      return { message: _('The lists update did not finish'), type: 'error' };
  }
}
