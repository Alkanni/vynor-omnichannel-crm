import {
  formatBookingTime,
  localDate,
  localDateTime,
  localTime,
  sortUpcomingFirst,
  startOfLocalDay,
} from '../helpers';

describe('booking helpers', () => {
  it('reads a time as a time input value and turns a date and time input back into an ISO 8601 time', () => {
    expect(localTime(new Date(2026, 10, 25, 9, 5))).toBe('09:05');
    expect(localDateTime('2026-11-25', '09:05')).toBe(
      new Date(2026, 10, 25, 9, 5).toISOString()
    );
  });

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
    expect(localDate(new Date(startOfLocalDay('2026-12-31', 1)))).toBe(
      '2027-01-01'
    );
  });

  it('counts a booking at the current time as upcoming and leaves the list as it was', () => {
    const now = Date.parse('2026-11-19T03:00:00Z');
    const bookings = [
      { id: 1, scheduled_at: '2026-11-19T02:59:00Z' },
      { id: 2, scheduled_at: '2026-11-19T03:00:00Z' },
    ];

    expect(sortUpcomingFirst(bookings, now).map(({ id }) => id)).toEqual([
      2, 1,
    ]);
    expect(bookings.map(({ id }) => id)).toEqual([1, 2]);
    expect(sortUpcomingFirst([], now)).toEqual([]);
  });

  it('formats a booking time in the time zone of the viewer', () => {
    const formatted = formatBookingTime('2026-11-20T03:00:00Z', 'en-GB');

    expect(formatted).toContain('Fri');
    expect(formatted).toContain('20 Nov 2026');
    expect(formatted).toContain('03:00');
  });
});
