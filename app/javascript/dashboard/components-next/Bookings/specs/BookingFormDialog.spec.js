import { flushPromises, shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import BookingFormDialog from '../BookingFormDialog.vue';

vi.mock('dashboard/api/bookings', () => ({
  default: { create: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const openDialog = vi.fn();
const closeDialog = vi.fn();
const DialogStub = {
  name: 'Dialog',
  props: ['title', 'disableConfirmButton'],
  emits: ['confirm'],
  setup(_, { expose }) {
    expose({ open: openDialog, close: closeDialog });
  },
  template: '<div><slot /></div>',
};

const mountForm = () =>
  shallowMount(BookingFormDialog, {
    props: { conversationId: 12 },
    global: { stubs: { Dialog: DialogStub, Banner: false } },
  });

const SLOT_TAKEN =
  'Booking #3 is already confirmed for Ganti oli at 2026-11-25 10:00 WIB. Choose another time or service.';

const values = wrapper =>
  wrapper
    .findAllComponents(Input)
    .map(input => [input.props('label'), input.props('modelValue')]);

const confirm = wrapper =>
  wrapper.findComponent(DialogStub).vm.$emit('confirm');

describe('BookingFormDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('starts a new booking with the customer name and the agent fields', async () => {
    const wrapper = mountForm();
    wrapper.vm.open({ customerName: 'Rina', fields: ['Plat nomor'] });
    await flushPromises();

    expect(openDialog).toHaveBeenCalled();
    expect(wrapper.findComponent(DialogStub).props('title')).toBe(
      'BOOKINGS.FORM.NEW_TITLE'
    );
    expect(values(wrapper)).toEqual([
      ['BOOKINGS.FORM.SERVICE', ''],
      ['BOOKINGS.FORM.CUSTOMER_NAME', 'Rina'],
      ['BOOKINGS.FORM.DATE', ''],
      ['BOOKINGS.FORM.TIME', ''],
      ['Plat nomor', ''],
    ]);
    expect(
      wrapper.findComponent(DialogStub).props('disableConfirmButton')
    ).toBe(true);
  });

  it('records the booking for the conversation, at the local date and time', async () => {
    const saved = { id: 9, status: 'confirmed' };
    BookingsAPI.create.mockResolvedValue({ data: saved });
    const wrapper = mountForm();
    wrapper.vm.open({ customerName: 'Rina', fields: ['Plat nomor'] });
    await flushPromises();

    const inputs = wrapper.findAllComponents(Input);
    inputs[0].vm.$emit('update:modelValue', 'Poles body');
    inputs[2].vm.$emit('update:modelValue', '2026-11-25');
    inputs[3].vm.$emit('update:modelValue', '10:00');
    inputs[4].vm.$emit('update:modelValue', 'B 9 XY');
    wrapper.findComponent(TextArea).vm.$emit('update:modelValue', 'Bawa STNK');
    await flushPromises();
    confirm(wrapper);
    await flushPromises();

    expect(BookingsAPI.create).toHaveBeenCalledWith({
      conversation_id: 12,
      service: 'Poles body',
      customer_name: 'Rina',
      scheduled_at: new Date(2026, 10, 25, 10, 0).toISOString(),
      notes: 'Bawa STNK',
      details: { 'Plat nomor': 'B 9 XY' },
    });
    expect(wrapper.emitted('saved')).toEqual([[saved]]);
    expect(closeDialog).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('BOOKINGS.FORM.SAVE_SUCCESS');
  });

  it('edits a booking with its own values, and keeps the form open when saving fails', async () => {
    BookingsAPI.update.mockRejectedValue(new Error('Unprocessable'));
    const wrapper = mountForm();
    const scheduledAt = new Date(2026, 10, 23, 9, 30).toISOString();
    wrapper.vm.open({
      current: {
        id: 4,
        service: 'Servis berkala',
        customer_name: 'Andi',
        scheduled_at: scheduledAt,
        notes: null,
        details: { Mobil: 'Avanza' },
      },
    });
    await flushPromises();

    expect(wrapper.findComponent(DialogStub).props('title')).toBe(
      'BOOKINGS.FORM.EDIT_TITLE'
    );
    expect(values(wrapper)).toEqual([
      ['BOOKINGS.FORM.SERVICE', 'Servis berkala'],
      ['BOOKINGS.FORM.CUSTOMER_NAME', 'Andi'],
      ['BOOKINGS.FORM.DATE', '2026-11-23'],
      ['BOOKINGS.FORM.TIME', '09:30'],
      ['Mobil', 'Avanza'],
    ]);

    confirm(wrapper);
    await flushPromises();

    expect(BookingsAPI.update).toHaveBeenCalledWith(4, {
      service: 'Servis berkala',
      customer_name: 'Andi',
      scheduled_at: scheduledAt,
      notes: '',
      details: { Mobil: 'Avanza' },
    });
    expect(closeDialog).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith('BOOKINGS.FORM.SAVE_ERROR');
    expect(wrapper.findComponent(Banner).exists()).toBe(false);
  });

  it('warns in the form about the confirmed booking that holds the slot, stays open, and forgets it on the next open', async () => {
    BookingsAPI.create.mockRejectedValue({
      response: {
        status: 422,
        data: { message: SLOT_TAKEN, error_code: 'booking_slot_taken' },
      },
    });
    const wrapper = mountForm();
    wrapper.vm.open({ customerName: 'Rina' });
    await flushPromises();

    const inputs = wrapper.findAllComponents(Input);
    inputs[0].vm.$emit('update:modelValue', 'Ganti oli');
    inputs[2].vm.$emit('update:modelValue', '2026-11-25');
    inputs[3].vm.$emit('update:modelValue', '10:00');
    await flushPromises();
    confirm(wrapper);
    await flushPromises();

    const warning = wrapper.findComponent(Banner);
    expect(warning.props('color')).toBe('amber');
    expect(warning.text()).toBe(SLOT_TAKEN);
    expect(closeDialog).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();

    wrapper.vm.open({ customerName: 'Rina' });
    await flushPromises();
    expect(wrapper.findComponent(Banner).exists()).toBe(false);
  });

  it('saves nothing until the service, name, date, and time are filled in', async () => {
    const wrapper = mountForm();
    wrapper.vm.open({ customerName: 'Rina' });
    await flushPromises();

    confirm(wrapper);
    await flushPromises();

    expect(BookingsAPI.create).not.toHaveBeenCalled();
  });
});
