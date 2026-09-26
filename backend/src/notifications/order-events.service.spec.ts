import { firstValueFrom, take, toArray } from 'rxjs';

import { OrderEventsService } from './order-events.service';

describe('OrderEventsService', () => {
  it('streams only the events of the requested order', async () => {
    const events = new OrderEventsService();
    const received = firstValueFrom(
      events.stream('order_1').pipe(take(2), toArray()),
    );

    events.emit('order_2', 'MATCHED');
    events.emit('order_1', 'MATCHED');
    events.emit('order_2', 'EN_ROUTE');
    events.emit('order_1', 'LOCATION');

    expect(await received).toEqual([
      { type: 'order', data: { type: 'MATCHED' } },
      { type: 'order', data: { type: 'LOCATION' } },
    ]);
  });
});
