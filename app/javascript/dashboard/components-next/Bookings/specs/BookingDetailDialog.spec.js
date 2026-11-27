import { onMounted } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import BookingDetailDialog from '../BookingDetailDialog.vue';
import { formatBookingTime } from '../helpers';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values ? `${key} ${JSON.stringify(values)}` : key),
    locale: { value: 'en-GB' },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));

const openDialog = vi.fn();
const DialogStub = {
  name: 'Dialog',
  props: ['title', 'cancelButtonLabel', 'showConfirmButton'],
  setup(_, { expose }) {
    expose({ open: openDialog });
  },
  template: '<div><slot /></div>',
};
const RouterLinkStub = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a><slot /></a>',
};
// Each mount loads the history.
const mountHistory = vi.fn();
const BookingHistoryStub = {
  name: 'BookingHistory',
  props: ['bookingId'],
  setup(props) {
    onMounted(() => mountHistory(props.bookingId));
  },
  template: '<div />',
};

const booking = {
  id: 12,
  status: 'cancelled',
  next_statuses: [],
  rescheduled_from_id: 9,
  scheduled_at: '2026-11-21T03:00:00Z',
  service: 'Ganti oli',
  customer_name: 'Budi Santoso',
  notes: 'Bawa STNK\nDatang pagi',
  details: { 'Nomor polisi': 'B 1234 CD', 'Kilometer saat ini': '' },
  contact: { id: 5, name: 'Budi', phone_number: '+6281234567890' },
  conversation: { id: 3, display_id: 7, inbox_id: 1 },
  ai_agent: { id: 2, name: 'Vynor' },
  created_at: '2026-11-20T08:30:00Z',
};

const mountDialog = () =>
  shallowMount(BookingDetailDialog, {
    global: {
      stubs: {
        Dialog: DialogStub,
        RouterLink: RouterLinkStub,
        BookingHistory: BookingHistoryStub,
      },
    },
  });

const openWith = async current => {
  const wrapper = mountDialog();
  wrapper.vm.open(current);
  await flushPromises();
  return wrapper;
};

const fields = wrapper =>
  wrapper
    .findAll('dl > div')
    .map(field => [field.find('dt').text(), field.find('dd').text()]);

describe('BookingDetailDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('opens with the booking number and only a close button', async () => {
    const wrapper = await openWith(booking);
    const dialog = wrapper.findComponent(DialogStub);

    expect(openDialog).toHaveBeenCalled();
    expect(dialog.props('title')).toBe('BOOKINGS.DETAIL.TITLE {"id":12}');
    expect(dialog.props('cancelButtonLabel')).toBe('GENERAL.CLOSE');
    expect(dialog.props('showConfirmButton')).toBe(false);
  });

  it('shows every field of the booking, the agent fields after the customer, and - for a blank one', async () => {
    const wrapper = await openWith(booking);

    expect(fields(wrapper)).toEqual([
      [
        'BOOKINGS.TABLE.SCHEDULE',
        formatBookingTime(booking.scheduled_at, 'en-GB'),
      ],
      ['BOOKINGS.TABLE.SERVICE', 'Ganti oli'],
      ['BOOKINGS.FORM.CUSTOMER_NAME', 'Budi Santoso'],
      ['BOOKINGS.DETAIL.CONTACT', 'Budi'],
      ['BOOKINGS.DETAIL.PHONE_NUMBER', '+6281234567890'],
      ['Nomor polisi', 'B 1234 CD'],
      ['Kilometer saat ini', '-'],
      ['BOOKINGS.DETAIL.AI_AGENT', 'Vynor'],
      [
        'BOOKINGS.DETAIL.RECORDED_AT',
        formatBookingTime(booking.created_at, 'en-GB'),
      ],
      ['BOOKINGS.FORM.NOTES', 'Bawa STNK\nDatang pagi'],
    ]);
  });

  it('keeps the line breaks of the notes', async () => {
    const wrapper = await openWith(booking);
    const notes = wrapper.findAll('dl > div').at(-1).find('dd');

    expect(notes.element.textContent.trim()).toBe('Bawa STNK\nDatang pagi');
    expect(notes.classes()).toContain('whitespace-pre-wrap');
  });

  it('shows the status with its colour and the booking it replaces', async () => {
    const wrapper = await openWith(booking);
    const badge = wrapper.find('span');

    expect(badge.text()).toBe('BOOKINGS.STATUS.CANCELLED');
    expect(badge.classes()).toContain('bg-n-slate-3');
    expect(wrapper.text()).toContain('BOOKINGS.RESCHEDULED_FROM {"id":9}');
  });

  it('shows - for a booking without phone number, agent, or notes, and no replaced booking', async () => {
    const wrapper = await openWith({
      ...booking,
      rescheduled_from_id: null,
      notes: null,
      contact: { id: 5, name: 'Budi', phone_number: null },
      ai_agent: null,
    });

    expect(fields(wrapper)).toEqual(
      expect.arrayContaining([
        ['BOOKINGS.DETAIL.PHONE_NUMBER', '-'],
        ['BOOKINGS.DETAIL.AI_AGENT', '-'],
        ['BOOKINGS.FORM.NOTES', '-'],
      ])
    );
    expect(wrapper.text()).not.toContain('BOOKINGS.RESCHEDULED_FROM');
  });

  it('links to the conversation of the booking', async () => {
    const wrapper = await openWith(booking);
    const link = wrapper.findComponent(RouterLinkStub);

    expect(link.props('to')).toEqual({
      name: 'inbox_conversation',
      params: { accountId: '1', conversation_id: 7 },
    });
    expect(link.text()).toBe('BOOKINGS.TABLE.OPEN_CONVERSATION {"id":7}');
  });

  it('shows the history of the booking, loaded again each time it opens', async () => {
    const wrapper = await openWith(booking);
    expect(mountHistory).toHaveBeenCalledWith(12);

    wrapper.vm.open(booking);
    await flushPromises();

    expect(mountHistory).toHaveBeenCalledTimes(2);
    expect(mountHistory).toHaveBeenLastCalledWith(12);
  });

  it('shows the booking it is opened with the next time', async () => {
    const wrapper = await openWith(booking);
    wrapper.vm.open({ ...booking, service: 'Tune up', status: 'confirmed' });
    await flushPromises();

    expect(fields(wrapper)).toContainEqual([
      'BOOKINGS.TABLE.SERVICE',
      'Tune up',
    ]);
    expect(wrapper.find('span').text()).toBe('BOOKINGS.STATUS.CONFIRMED');
  });
});
