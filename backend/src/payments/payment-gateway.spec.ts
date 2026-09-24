import Stripe from 'stripe';

import {
  confirmedPaymentFromStripeEvent,
  StripePaymentGateway,
} from './payment-gateway';

const request = {
  paymentId: 'pay_1',
  orderId: 'order_1',
  orderNo: 'FG2609240001',
  amount: 43400,
};

function fakeStripe(overrides: Partial<Record<string, jest.Mock>> = {}) {
  const create = jest.fn().mockResolvedValue({
    id: 'pi_new',
    status: 'requires_action',
    next_action: {
      promptpay_display_qr_code: {
        data: '00020101021230...PROMPTPAY',
        hosted_instructions_url: 'https://pay.stripe.com/qr/x',
        image_url_png: 'https://x/png',
        image_url_svg: 'https://x/svg',
      },
    },
  });
  const retrieve = jest.fn().mockResolvedValue({ status: 'requires_action' });
  const cancel = jest.fn().mockResolvedValue({});
  const stripe = {
    paymentIntents: { create, retrieve, cancel, ...overrides },
  } as unknown as Stripe;
  return { stripe, create, retrieve, cancel };
}

describe('StripePaymentGateway', () => {
  it('creates a confirmed THB PromptPay intent tagged with the payment id', async () => {
    const { stripe, create } = fakeStripe();
    const qr = await new StripePaymentGateway(
      stripe,
      'pay@fixgo.test',
    ).createPromptPay(request);
    expect(qr.chargeId).toBe('pi_new');
    expect(qr.qrPayload).toBe('00020101021230...PROMPTPAY');
    const [params] = create.mock.calls[0];
    expect(params).toMatchObject({
      amount: 43400,
      currency: 'thb',
      payment_method_types: ['promptpay'],
      confirm: true,
      metadata: { paymentId: 'pay_1', orderId: 'order_1' },
      payment_method_data: {
        type: 'promptpay',
        billing_details: { email: 'pay@fixgo.test' },
      },
    });
  });

  it('cancels the previous open intent before issuing a new QR', async () => {
    const { stripe, cancel } = fakeStripe();
    await new StripePaymentGateway(stripe, 'pay@fixgo.test').createPromptPay({
      ...request,
      previousChargeId: 'pi_old',
    });
    expect(cancel).toHaveBeenCalledWith('pi_old');
  });

  it('fails when Stripe does not return a QR code', async () => {
    const { stripe } = fakeStripe({
      create: jest
        .fn()
        .mockResolvedValue({ id: 'pi_x', status: 'requires_payment_method' }),
    });
    await expect(
      new StripePaymentGateway(stripe, 'pay@fixgo.test').createPromptPay(
        request,
      ),
    ).rejects.toThrow('QR');
  });
});

describe('confirmedPaymentFromStripeEvent', () => {
  const event = (type: string, metadata: Record<string, string>) =>
    ({
      type,
      data: {
        object: {
          id: 'pi_1',
          amount_received: 43400,
          currency: 'thb',
          metadata,
        },
      },
    }) as unknown as Stripe.Event;

  it('maps a succeeded intent to the payment it was created for', () => {
    expect(
      confirmedPaymentFromStripeEvent(
        event('payment_intent.succeeded', { paymentId: 'pay_1' }),
      ),
    ).toEqual({
      paymentId: 'pay_1',
      chargeId: 'pi_1',
      amountReceived: 43400,
      currency: 'thb',
    });
  });

  it('ignores other events and intents without our metadata', () => {
    expect(
      confirmedPaymentFromStripeEvent(
        event('payment_intent.processing', { paymentId: 'pay_1' }),
      ),
    ).toBeNull();
    expect(
      confirmedPaymentFromStripeEvent(event('payment_intent.succeeded', {})),
    ).toBeNull();
  });

  it('only trusts events whose signature verifies', () => {
    const payload = JSON.stringify({
      id: 'evt_1',
      type: 'payment_intent.succeeded',
    });
    const secret = 'whsec_test';
    const header = Stripe.webhooks.generateTestHeaderString({
      payload,
      secret,
    });
    expect(Stripe.webhooks.constructEvent(payload, header, secret).id).toBe(
      'evt_1',
    );
    expect(() =>
      Stripe.webhooks.constructEvent(payload, header, 'whsec_other'),
    ).toThrow();
  });
});
