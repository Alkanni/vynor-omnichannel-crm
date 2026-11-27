import { flushPromises, mount } from '@vue/test-utils';
import BookingsAPI from 'dashboard/api/bookings';
import BookingHistory from '../BookingHistory.vue';
import { formatBookingTime } from '../helpers';

vi.mock('dashboard/api/bookings', () => ({ default: { history: vi.fn() } }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => [key, ...Object.values(values)].join(' '),
    locale: { value: 'en-GB' },
  }),
}));

const entries = [
  {
    id: 1,
    action: 'create',
    actor: { type: 'AiAgent', id: 2, name: 'Vynor' },
    changes: [
      { field: 'status', from: null, to: 'requested' },
      { field: 'service', from: null, to: 'Ganti oli' },
      { field: 'scheduled_at', from: null, to: '2026-11-21T03:00:00.000Z' },
      { field: 'notes', from: null, to: null },
      {
        field: 'details',
        from: null,
        to: { 'Nomor polisi': 'B 1234 CD', 'Kilometer saat ini': '' },
      },
    ],
    comment: null,
    created_at: '2026-11-20T08:30:00Z',
  },
  {
    id: 2,
    action: 'update',
    actor: { type: 'User', id: 5, name: 'Sari' },
    changes: [
      { field: 'service', from: 'Ganti oli', to: 'Tune up' },
      {
        field: 'details',
        from: { 'Nomor polisi': 'B 1234 CD', 'Kilometer saat ini': '' },
        to: { 'Nomor polisi': 'B 1234 CD', 'Kilometer saat ini': '12000' },
      },
    ],
    comment: null,
    created_at: '2026-11-20T09:00:00Z',
  },
  {
    id: 3,
    action: 'update',
    actor: { type: 'User', id: 9, name: null },
    changes: [{ field: 'status', from: 'requested', to: 'cancelled' }],
    comment: 'Customer sakit',
    created_at: '2026-11-20T10:00:00Z',
  },
];

const mountHistory = async payload => {
  BookingsAPI.history.mockResolvedValue({ data: { payload } });
  const wrapper = mount(BookingHistory, { props: { bookingId: 12 } });
  await flushPromises();
  return wrapper;
};

const items = wrapper =>
  wrapper.findAll('ol > li').map(item => ({
    summary: item.find('span').text(),
    time: item.find('time').text(),
    lines: item.findAll('ul > li').map(line => line.text()),
    comment: item.find('p').exists() ? item.find('p').text() : null,
  }));

describe('BookingHistory', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('loads the history of the booking and says so meanwhile', async () => {
    BookingsAPI.history.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(BookingHistory, { props: { bookingId: 12 } });

    expect(BookingsAPI.history).toHaveBeenCalledWith(12);
    expect(wrapper.text()).toContain('BOOKINGS.HISTORY.LOADING');
  });

  it('lists each entry oldest first with who made it, when, and each value', async () => {
    const wrapper = await mountHistory(entries);

    expect(items(wrapper)).toEqual([
      {
        summary:
          'BOOKINGS.HISTORY.CREATED BOOKINGS.HISTORY.AI_AGENT_ACTOR Vynor',
        time: formatBookingTime('2026-11-20T08:30:00Z', 'en-GB'),
        lines: [
          'BOOKINGS.FIELD_VALUE BOOKINGS.TABLE.STATUS BOOKINGS.STATUS.REQUESTED',
          'BOOKINGS.FIELD_VALUE BOOKINGS.TABLE.SERVICE Ganti oli',
          `BOOKINGS.FIELD_VALUE BOOKINGS.TABLE.SCHEDULE ${formatBookingTime('2026-11-21T03:00:00.000Z', 'en-GB')}`,
          'BOOKINGS.FIELD_VALUE BOOKINGS.FORM.NOTES -',
          'BOOKINGS.FIELD_VALUE Nomor polisi B 1234 CD',
          'BOOKINGS.FIELD_VALUE Kilometer saat ini -',
        ],
        comment: null,
      },
      {
        summary: 'BOOKINGS.HISTORY.UPDATED Sari',
        time: formatBookingTime('2026-11-20T09:00:00Z', 'en-GB'),
        lines: [
          'BOOKINGS.HISTORY.FIELD_CHANGE BOOKINGS.TABLE.SERVICE Ganti oli Tune up',
          'BOOKINGS.HISTORY.FIELD_CHANGE Kilometer saat ini - 12000',
        ],
        comment: null,
      },
      {
        summary: 'BOOKINGS.HISTORY.UPDATED BOOKINGS.HISTORY.UNKNOWN_ACTOR',
        time: formatBookingTime('2026-11-20T10:00:00Z', 'en-GB'),
        lines: [
          'BOOKINGS.HISTORY.FIELD_CHANGE BOOKINGS.TABLE.STATUS BOOKINGS.STATUS.REQUESTED BOOKINGS.STATUS.CANCELLED',
        ],
        comment: 'BOOKINGS.HISTORY.REASON Customer sakit',
      },
    ]);
  });

  it('shows values as text, never as HTML', async () => {
    const wrapper = await mountHistory([
      {
        ...entries[1],
        changes: [
          { field: 'notes', from: null, to: '<b>Bawa STNK</b>' },
          { field: 'details', from: {}, to: { '<i>Plat</i>': '<img>' } },
        ],
      },
    ]);

    expect(wrapper.find('b').exists()).toBe(false);
    expect(wrapper.find('i').exists()).toBe(false);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(items(wrapper)[0].lines).toEqual([
      'BOOKINGS.HISTORY.FIELD_CHANGE BOOKINGS.FORM.NOTES - <b>Bawa STNK</b>',
      'BOOKINGS.HISTORY.FIELD_CHANGE <i>Plat</i> - <img>',
    ]);
  });

  it('says so for a booking without history', async () => {
    const wrapper = await mountHistory([]);

    expect(wrapper.find('ol').exists()).toBe(false);
    expect(wrapper.text()).toContain('BOOKINGS.HISTORY.EMPTY');
  });

  it('says so when the history cannot be loaded', async () => {
    BookingsAPI.history.mockRejectedValue(new Error('Network Error'));
    const wrapper = mount(BookingHistory, { props: { bookingId: 12 } });
    await flushPromises();

    expect(wrapper.text()).toContain('BOOKINGS.HISTORY.LOAD_ERROR');
    expect(wrapper.text()).not.toContain('BOOKINGS.HISTORY.LOADING');
  });
});
