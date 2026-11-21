import { flushPromises, shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import BookingStatusMenu from '../BookingStatusMenu.vue';

vi.mock('dashboard/api/bookings', () => ({ default: { update: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const booking = {
  id: 7,
  status: 'requested',
  next_statuses: ['confirmed', 'cancelled', 'completed', 'no_show'],
  service: 'Cuci salon',
};

const openDialog = vi.fn();
const closeDialog = vi.fn();
const DialogStub = {
  name: 'Dialog',
  emits: ['confirm'],
  setup(_, { expose }) {
    expose({ open: openDialog, close: closeDialog });
    return () => null;
  },
};

const mountMenu = (props = booking) =>
  shallowMount(BookingStatusMenu, {
    props: { booking: props },
    global: { stubs: { Dialog: DialogStub } },
  });

const pickStatus = (wrapper, status) =>
  wrapper.findComponent(SelectMenu).vm.$emit('update:modelValue', status);

describe('BookingStatusMenu', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the status and offers it with the statuses it may change to, in order', () => {
    const wrapper = mountMenu();

    expect(wrapper.text()).toContain('BOOKINGS.STATUS.REQUESTED');
    expect(wrapper.findComponent(SelectMenu).props('options')).toEqual([
      { value: 'requested', label: 'BOOKINGS.STATUS.REQUESTED' },
      { value: 'confirmed', label: 'BOOKINGS.STATUS.CONFIRMED' },
      { value: 'cancelled', label: 'BOOKINGS.STATUS.CANCELLED' },
      { value: 'completed', label: 'BOOKINGS.STATUS.COMPLETED' },
      { value: 'no_show', label: 'BOOKINGS.STATUS.NO_SHOW' },
    ]);
  });

  it('offers a completed booking only the correction to no-show', () => {
    const wrapper = mountMenu({
      ...booking,
      status: 'completed',
      next_statuses: ['no_show'],
    });

    expect(wrapper.findComponent(SelectMenu).props('options')).toEqual([
      { value: 'completed', label: 'BOOKINGS.STATUS.COMPLETED' },
      { value: 'no_show', label: 'BOOKINGS.STATUS.NO_SHOW' },
    ]);
  });

  it('shows a cancelled booking without a menu', () => {
    const wrapper = mountMenu({
      ...booking,
      status: 'cancelled',
      next_statuses: [],
    });

    expect(wrapper.text()).toContain('BOOKINGS.STATUS.CANCELLED');
    expect(wrapper.findComponent(SelectMenu).exists()).toBe(false);
  });

  it('saves a new status and passes on the updated booking', async () => {
    const updated = { ...booking, status: 'confirmed' };
    BookingsAPI.update.mockResolvedValue({ data: updated });
    const wrapper = mountMenu();

    pickStatus(wrapper, 'confirmed');
    await flushPromises();

    expect(openDialog).not.toHaveBeenCalled();
    expect(BookingsAPI.update).toHaveBeenCalledWith(7, { status: 'confirmed' });
    expect(wrapper.emitted('updated')).toEqual([[updated]]);
    expect(useAlert).toHaveBeenCalledWith('BOOKINGS.UPDATE_SUCCESS');
  });

  it('asks before cancelling, and cancels only once the user confirms', async () => {
    const updated = { ...booking, status: 'cancelled', next_statuses: [] };
    BookingsAPI.update.mockResolvedValue({ data: updated });
    const wrapper = mountMenu();

    pickStatus(wrapper, 'cancelled');
    await flushPromises();

    expect(openDialog).toHaveBeenCalledTimes(1);
    expect(BookingsAPI.update).not.toHaveBeenCalled();

    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(closeDialog).toHaveBeenCalledTimes(1);
    expect(BookingsAPI.update).toHaveBeenCalledWith(7, { status: 'cancelled' });
    expect(wrapper.emitted('updated')).toEqual([[updated]]);
  });

  it('does not save the status the booking already has', async () => {
    const wrapper = mountMenu();

    pickStatus(wrapper, 'requested');
    await flushPromises();

    expect(BookingsAPI.update).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });

  it('ignores another pick while a status is being saved', async () => {
    BookingsAPI.update.mockReturnValue(new Promise(() => {}));
    const wrapper = mountMenu();

    pickStatus(wrapper, 'confirmed');
    pickStatus(wrapper, 'cancelled');
    await flushPromises();

    expect(BookingsAPI.update).toHaveBeenCalledTimes(1);
    expect(openDialog).not.toHaveBeenCalled();
  });

  it('tells the user when the status could not be saved', async () => {
    BookingsAPI.update.mockRejectedValue(new Error('Network Error'));
    const wrapper = mountMenu();

    pickStatus(wrapper, 'confirmed');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('BOOKINGS.UPDATE_ERROR');
    expect(wrapper.emitted('updated')).toBeUndefined();
  });
});
