import {
  enableAutoUnmount,
  flushPromises,
  shallowMount,
} from '@vue/test-utils';
import BookingsAPI from 'dashboard/api/bookings';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import BookingsPage from '../BookingsPage.vue';

const { enabledFlags } = await vi.hoisted(async () => {
  const { ref } = await import('vue');
  return { enabledFlags: ref([]) };
});

vi.mock('dashboard/api/bookings', () => ({ default: { list: vi.fn() } }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => enabledFlags.value.includes(flag),
  }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'en-GB' } }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));

// Today in the viewer's time zone (TZ=UTC in the test run).
const TODAY = '2026-11-20T00:00:00.000Z';

const openForm = vi.fn();
const FormStub = {
  name: 'BookingFormDialog',
  emits: ['saved'],
  setup(_, { expose }) {
    expose({ open: openForm });
    return () => null;
  },
};

const openDetail = vi.fn();
const DetailStub = {
  name: 'BookingDetailDialog',
  setup(_, { expose }) {
    expose({ open: openDetail });
    return () => null;
  },
};

// The table renders its rows through slots, which shallow stubs leave out.
const tableStubs = {
  BaseTable: {
    props: ['items'],
    template: '<div><slot name="row" :items="items" /></div>',
  },
  BaseTableRow: { template: '<div><slot /></div>' },
  BaseTableCell: { template: '<div><slot /></div>' },
};

const mountPage = () =>
  shallowMount(BookingsPage, {
    global: {
      stubs: {
        RouterLink: true,
        BookingFormDialog: FormStub,
        BookingDetailDialog: DetailStub,
        ...tableStubs,
      },
    },
  });

const lastListParams = () => BookingsAPI.list.mock.lastCall[0];

describe('BookingsPage', () => {
  // The flags are shared, so a page left mounted would fetch when a later example changes them.
  enableAutoUnmount(afterEach);

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-20T10:00:00Z'));
    enabledFlags.value = ['bookings'];
    BookingsAPI.list.mockResolvedValue({
      data: { payload: [], meta: { count: 60, current_page: 1 } },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('loads nothing and says so while the account lacks the bookings feature', async () => {
    enabledFlags.value = [];
    const wrapper = mountPage();
    await flushPromises();

    expect(BookingsAPI.list).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('BOOKINGS.DISABLED');
  });

  it('loads the first page of bookings from today on', async () => {
    mountPage();
    await flushPromises();

    expect(BookingsAPI.list).toHaveBeenCalledTimes(1);
    expect(lastListParams()).toEqual({
      status: undefined,
      from: TODAY,
      to: undefined,
      page: 1,
    });
  });

  it('loads the bookings once the account features arrive after the page', async () => {
    enabledFlags.value = [];
    mountPage();
    await flushPromises();

    enabledFlags.value = ['bookings'];
    await flushPromises();

    expect(BookingsAPI.list).toHaveBeenCalledTimes(1);
  });

  it('goes back to the first page with one request when the status tab changes', async () => {
    const wrapper = mountPage();
    await flushPromises();
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    expect(lastListParams()).toMatchObject({ page: 2 });

    wrapper.findComponent(TabBar).vm.$emit('tabChanged', {
      value: 'confirmed',
    });
    await flushPromises();

    expect(BookingsAPI.list).toHaveBeenCalledTimes(3);
    expect(lastListParams()).toEqual({
      status: 'confirmed',
      from: TODAY,
      to: undefined,
      page: 1,
    });
  });

  it('includes the whole To day by ending the range at the start of the next day', async () => {
    const wrapper = mountPage();
    await flushPromises();

    wrapper
      .findAllComponents(Input)[1]
      .vm.$emit('update:modelValue', '2026-11-30');
    await flushPromises();

    expect(lastListParams()).toMatchObject({
      from: TODAY,
      to: '2026-12-01T00:00:00.000Z',
    });
  });

  it('says when the bookings could not be loaded', async () => {
    BookingsAPI.list.mockRejectedValue(new Error('Network Error'));
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('BOOKINGS.LOAD_ERROR');
  });

  describe('with a booking that can still change and a cancelled one', () => {
    const row = (id, status, nextStatuses) => ({
      id,
      status,
      next_statuses: nextStatuses,
      scheduled_at: '2026-11-21T03:00:00Z',
      service: 'Cuci salon',
      customer_name: 'Budi',
      notes: null,
      details: {},
      contact: { id: 5, name: 'Budi', phone_number: null },
      conversation: { id: 3, display_id: 7, inbox_id: 1 },
    });
    const editable = row(1, 'confirmed', ['cancelled', 'completed', 'no_show']);
    const cancelled = row(2, 'cancelled', []);

    const buttons = (wrapper, label) =>
      wrapper
        .findAllComponents(Button)
        .filter(button => button.attributes('aria-label') === label);

    beforeEach(() => {
      BookingsAPI.list.mockResolvedValue({
        data: {
          payload: [editable, cancelled],
          meta: { count: 2, current_page: 1 },
        },
      });
    });

    it('edits a booking that can still change, and shows it as saved', async () => {
      const wrapper = mountPage();
      await flushPromises();

      const edits = buttons(wrapper, 'BOOKINGS.FORM.EDIT');
      expect(edits).toHaveLength(1);
      edits[0].vm.$emit('click');
      expect(openForm).toHaveBeenCalledWith({ current: editable });

      wrapper
        .findComponent(FormStub)
        .vm.$emit('saved', { ...editable, service: 'Poles body' });
      await flushPromises();
      expect(wrapper.text()).toContain('Poles body');
    });

    it('shows the details of every booking, the cancelled one too', async () => {
      const wrapper = mountPage();
      await flushPromises();

      const details = buttons(wrapper, 'BOOKINGS.DETAIL.VIEW');
      expect(details).toHaveLength(2);
      details[1].vm.$emit('click');
      expect(openDetail).toHaveBeenCalledWith(cancelled);
    });

    it('shows the details of a booking as it was last saved', async () => {
      const wrapper = mountPage();
      await flushPromises();
      const saved = { ...editable, service: 'Poles body' };
      wrapper.findComponent(FormStub).vm.$emit('saved', saved);
      await flushPromises();

      buttons(wrapper, 'BOOKINGS.DETAIL.VIEW')[0].vm.$emit('click');
      expect(openDetail).toHaveBeenCalledWith(saved);
    });
  });
});
