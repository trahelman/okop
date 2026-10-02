import { ValidationResult } from './types';

// The backend adds a tag to the value with jq: an array, a string or null made the whole sing-box
// configuration fail, and an object without "type" is rejected by sing-box
export function validateOutboundJson(value: string): ValidationResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    return { valid: false, message: _('Invalid JSON format') };
  }

  if (
    typeof parsed !== 'object' ||
    parsed === null ||
    Array.isArray(parsed) ||
    typeof (parsed as { type?: unknown }).type !== 'string'
  ) {
    return {
      valid: false,
      message: _('Outbound must be a JSON object with a "type" field'),
    };
  }

  return { valid: true, message: _('Valid') };
}
