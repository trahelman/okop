import { describe, it, expect } from 'vitest';
import { validateOutboundJson } from '../validateOutboundJson';

const validValues = [
  [
    'socks outbound',
    '{"type":"socks","server":"127.0.0.1","server_port":1080}',
  ],
  ['direct outbound', '{ "type": "direct" }'],
];

const invalidValues = [
  ['not JSON', '{type: socks}'],
  ['array', '[{"type":"socks"}]'],
  ['string', '"socks"'],
  ['number', '42'],
  ['null', 'null'],
  ['object without type', '{"server":"127.0.0.1"}'],
  ['type is not a string', '{"type":1}'],
];

describe('validateOutboundJson', () => {
  describe.each(validValues)('Valid: %s', (_desc, value) => {
    it(`returns valid=true for ${value}`, () => {
      expect(validateOutboundJson(value).valid).toBe(true);
    });
  });

  describe.each(invalidValues)('Invalid: %s', (_desc, value) => {
    it(`returns valid=false for ${value}`, () => {
      expect(validateOutboundJson(value).valid).toBe(false);
    });
  });
});
