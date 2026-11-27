import { flushPromises, shallowMount } from '@vue/test-utils';
import BookingsAPI from 'dashboard/api/bookings';
import Button from 'dashboard/components-next/button/Button.vue';
import BookingStatusMenu from '../BookingStatusMenu.vue';
import ContactBookings from '../ContactBookings.vue';

vi.mock('dashboard/api/bookings', () => ({
  default: { list: vi.fn() },
}));
vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return {
    useI18n: () => ({
      t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
      locale: ref('en-GB'),
    }),
  };
});

const booking = (id, service, scheduledAt) => ({
  id,
  service,
  scheduled_at: scheduledAt,
  status: 'requested',
  next_statuses: ['confirmed', 'cancelled', 'completed', 'no_show'],
  notes: null,
  details: {},
});
const past = booking(1, 'Servis lama', '2020-01-10T03:00:00Z');
const upcoming = booking(2, 'Cuci salon', '2100-01-10T03:00:00Z');

const openForm = vi.fn();
const FormStub = {
  name: 'BookingFormDialog',
  emits: ['saved'],
  setup(_, { expose }) {
    expose({ open: openForm });
    return () => null;
  },
};

const mountPanel = (contactId = 5, props = {}) =>
  shallowMount(ContactBookings, {
    props: { contactId, ...props },
    global: { stubs: { BookingFormDialog: FormStub } },
  });

const editButtons = wrapper =>
  wrapper
    .findAllComponents(Button)
    .filter(button => button.attributes('aria-label') === 'BOOKINGS.FORM.EDIT');

const services = wrapper =>
  wrapper.findAll('li .text-heading-3').map(service => service.text());

describe('ContactBookings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('lists the bookings of the contact, upcoming ones first', async () => {
    BookingsAPI.list.mockResolvedValue({
      data: { payload: [past, upcoming] },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(BookingsAPI.list).toHaveBeenCalledWith({ contact_id: 5 });
    expect(services(wrapper)).toEqual(['Cuci salon', 'Servis lama']);
  });

  it('names the booking a rescheduled one replaces', async () => {
    BookingsAPI.list.mockResolvedValue({
      data: { payload: [{ ...upcoming, rescheduled_from_id: 1 }] },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('BOOKINGS.RESCHEDULED_FROM {"id":1}');
  });

  it('shows the fields of a booking, with a dash for a blank one, and its notes', async () => {
    BookingsAPI.list.mockResolvedValue({
      data: {
        payload: [
          {
            ...upcoming,
            notes: 'Bawa STNK',
            details: { 'Plat nomor': 'B 1234 CD', Warna: '' },
          },
        ],
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'BOOKINGS.FIELD_VALUE {"field":"Plat nomor","value":"B 1234 CD"}'
    );
    expect(wrapper.text()).toContain(
      'BOOKINGS.FIELD_VALUE {"field":"Warna","value":"-"}'
    );
    expect(wrapper.text()).toContain('Bawa STNK');
  });

  it('says when the contact has no bookings', async () => {
    BookingsAPI.list.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('BOOKINGS.PANEL_EMPTY');
  });

  it('says when the bookings could not be loaded', async () => {
    BookingsAPI.list.mockRejectedValue(new Error('Network Error'));
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('BOOKINGS.LOAD_ERROR');
  });

  it('loads the bookings again for another contact', async () => {
    BookingsAPI.list.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.setProps({ contactId: 9 });
    await flushPromises();

    expect(BookingsAPI.list).toHaveBeenLastCalledWith({ contact_id: 9 });
    expect(BookingsAPI.list).toHaveBeenCalledTimes(2);
  });

  it('shows a booking as the status menu updated it', async () => {
    BookingsAPI.list.mockResolvedValue({ data: { payload: [upcoming] } });
    const wrapper = mountPanel();
    await flushPromises();

    const menu = wrapper.findComponent(BookingStatusMenu);
    menu.vm.$emit('updated', { ...upcoming, status: 'confirmed' });
    await wrapper.vm.$nextTick();

    expect(menu.props('booking')).toMatchObject({ id: 2, status: 'confirmed' });
  });

  it('adds a booking to the open conversation with the contact name', async () => {
    BookingsAPI.list.mockResolvedValue({ data: { payload: [upcoming] } });
    const wrapper = mountPanel(5, { conversationId: 12, contactName: 'Rina' });
    await flushPromises();

    const add = wrapper
      .findAllComponents(Button)
      .find(button => button.props('label') === 'BOOKINGS.FORM.ADD');
    add.vm.$emit('click');
    await flushPromises();

    expect(openForm).toHaveBeenCalledWith({ customerName: 'Rina' });

    const added = { ...booking(9, 'Poles body', '2101-01-10T03:00:00Z') };
    wrapper.findComponent(FormStub).vm.$emit('saved', added);
    await wrapper.vm.$nextTick();
    expect(services(wrapper)).toEqual(['Cuci salon', 'Poles body']);
  });

  it('offers no add button without a conversation', async () => {
    BookingsAPI.list.mockResolvedValue({ data: { payload: [] } });

    expect(
      mountPanel()
        .findAllComponents(Button)
        .some(button => button.props('label') === 'BOOKINGS.FORM.ADD')
    ).toBe(false);
  });

  it('edits a booking that can still change, and shows it as saved', async () => {
    const cancelled = {
      ...booking(3, 'Spooring', '2100-02-10T03:00:00Z'),
      status: 'cancelled',
      next_statuses: [],
    };
    BookingsAPI.list.mockResolvedValue({
      data: { payload: [upcoming, cancelled] },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(editButtons(wrapper)).toHaveLength(1);
    editButtons(wrapper)[0].vm.$emit('click');
    expect(openForm).toHaveBeenCalledWith({ current: upcoming });

    wrapper
      .findComponent(FormStub)
      .vm.$emit('saved', { ...upcoming, service: 'Poles body' });
    await wrapper.vm.$nextTick();
    expect(services(wrapper)).toEqual(['Poles body', 'Spooring']);
  });
});
