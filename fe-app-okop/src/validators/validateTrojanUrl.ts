import { ValidationResult } from './types';
import { parseQueryString } from '../helpers/parseQueryString';

export function validateTrojanUrl(url: string): ValidationResult {
  try {
    if (!url.startsWith('trojan://')) {
      return {
        valid: false,
        message: _('Invalid Trojan URL: must start with trojan://'),
      };
    }

    if (!url || /\s/.test(url)) {
      return {
        valid: false,
        message: _('Invalid Trojan URL: must not contain spaces'),
      };
    }

    const body = url.slice('trojan://'.length);
    const [mainPart] = body.split('#');
    const [userHostPort, queryString] = mainPart.split('?');

    const [userPart, hostPortPart] = userHostPort.split('@');

    if (!userHostPort)
      return {
        valid: false,
        message: 'Invalid Trojan URL: missing credentials and host',
      };

    if (!userPart)
      return { valid: false, message: 'Invalid Trojan URL: missing password' };

    if (!hostPortPart)
      return {
        valid: false,
        message: 'Invalid Trojan URL: missing hostname and port',
      };

    const [host, port] = hostPortPart.split(':');

    if (!host)
      return { valid: false, message: 'Invalid Trojan URL: missing hostname' };

    if (!port)
      return { valid: false, message: 'Invalid Trojan URL: missing port' };

    const portNum = Number(port);

    if (!Number.isInteger(portNum) || portNum < 1 || portNum > 65535)
      return {
        valid: false,
        message: 'Invalid Trojan URL: invalid port number',
      };

    // Transports sing-box has and okop builds, mKCP and XHTTP exist only in Xray
    const params = parseQueryString(queryString ?? '');
    const validTypes = ['tcp', 'raw', 'grpc', 'httpupgrade', 'ws'];
    if (params.type && !validTypes.includes(params.type))
      return {
        valid: false,
        message: 'Invalid Trojan URL: unsupported type',
      };
  } catch (_e) {
    return { valid: false, message: _('Invalid Trojan URL: parsing failed') };
  }

  return { valid: true, message: _('Valid') };
}
