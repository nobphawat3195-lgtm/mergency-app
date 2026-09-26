import { crc16, normalizePromptPayId, promptPayPayload } from './promptpay-qr';

describe('PromptPay QR payload', () => {
  it('uses CRC-16/CCITT-FALSE', () => {
    // ค่าตรวจสอบมาตรฐานของ CRC-16/CCITT-FALSE
    expect(crc16('123456789')).toBe('29B1');
  });

  it('encodes a phone number PromptPay with a locked amount', () => {
    const payload = promptPayPayload('081-234-5678', 43400);
    expect(payload.startsWith('000201010212')).toBe(true);
    expect(payload).toContain('29370016A00000067701011101130066812345678');
    expect(payload).toContain('5303764');
    expect(payload).toContain('5406434.00');
    expect(payload).toContain('5802TH');
    const body = payload.slice(0, -4);
    expect(body.endsWith('6304')).toBe(true);
    expect(payload.slice(-4)).toBe(crc16(body));
  });

  it('encodes a 13-digit tax id as sub-tag 02', () => {
    const payload = promptPayPayload('0105561234567', 199000);
    expect(payload).toContain('0213' + '0105561234567');
    expect(payload).toContain('54071990.00');
  });

  it('rejects ids and amounts that banks would refuse', () => {
    expect(() => normalizePromptPayId('12345')).toThrow('PROMPTPAY_ID');
    expect(() => promptPayPayload('0812345678', 0)).toThrow();
    expect(() => promptPayPayload('0812345678', 10.5)).toThrow();
  });
});

describe('ManualPromptPayGateway', () => {
  it('issues a scannable QR for the company PromptPay without a gateway call', async () => {
    const { ManualPromptPayGateway } = await import('./payment-gateway');
    const gateway = new ManualPromptPayGateway('0812345678', 'บจก. ฟิกซ์โก');
    const qr = await gateway.createPromptPay({
      paymentId: 'pay_1',
      orderId: 'order_1',
      orderNo: 'FG1',
      amount: 45000,
    });
    expect(qr.chargeId).toBe('manual_pay_1');
    expect(qr.qrPayload).toBe(promptPayPayload('0812345678', 45000));
    expect(gateway.payeeName).toBe('บจก. ฟิกซ์โก');
  });

  it('refuses to start with an invalid PromptPay id', async () => {
    const { ManualPromptPayGateway } = await import('./payment-gateway');
    expect(() => new ManualPromptPayGateway('123', 'x')).toThrow(
      'PROMPTPAY_ID',
    );
  });
});
