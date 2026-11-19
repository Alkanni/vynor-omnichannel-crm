import { localDate, sortUpcomingFirst, startOfLocalDay } from '../helpers';

describe('booking helpers', () => {
  it('sorts upcoming bookings soonest first, then past ones latest first', () => {
    const now = Date.parse('2026-11-19T03:00:00Z');
    const bookings = [
      { id: 1, scheduled_at: '2026-11-18T03:00:00Z' },
      { id: 2, scheduled_at: '2026-11-22T03:00:00Z' },
      { id: 3, scheduled_at: '2026-11-17T03:00:00Z' },
      { id: 4, scheduled_at: '2026-11-20T03:00:00Z' },
    ];

    expect(sortUpcomingFirst(bookings, now).map(({ id }) => id)).toEqual([
      4, 2, 1, 3,
    ]);
  });

  it('turns a date input value into the start of that local day, or a later one', () => {
    const start = new Date(startOfLocalDay('2026-11-30'));
    const nextDay = new Date(startOfLocalDay('2026-11-30', 1));

    expect(localDate(start)).toBe('2026-11-30');
    expect([start.getHours(), start.getMinutes()]).toEqual([0, 0]);
    expect(localDate(nextDay)).toBe('2026-12-01');
  });
});
