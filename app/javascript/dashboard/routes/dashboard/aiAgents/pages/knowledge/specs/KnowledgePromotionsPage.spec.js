import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import KnowledgePromotionsPage from '../KnowledgePromotionsPage.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: { getPromotions: vi.fn(), bulkDeletePromotions: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      AI_AGENTS: {
        KNOWLEDGE: {
          PROMOTION: {
            FILTERS: { ALL: 'All' },
            STATUS: {
              ACTIVE: 'Active',
              SCHEDULED: 'Scheduled',
              ARCHIVED: 'Archived',
            },
            PERIOD: {
              RANGE: '{from} to {to}',
              FROM: 'From {from}, no end date',
              UNTIL: 'Until {to}',
              ALWAYS: 'No end date',
            },
            APPLIES_TO: 'Applies to: {products}',
          },
        },
      },
    },
  },
});

const PROMOTIONS = [
  {
    id: 3,
    title: 'Diskon November',
    description: 'Stabill Rp80.000',
    starts_on: '2026-11-01',
    ends_on: '2026-11-30',
    status: 'active',
    products: [
      { id: 1, name: 'Stabill' },
      { id: 2, name: 'Oli Mesin' },
    ],
  },
  {
    id: 2,
    title: 'Akhir tahun',
    description: 'Diskon 10%',
    starts_on: '2026-12-20',
    ends_on: null,
    status: 'scheduled',
    products: [],
  },
  {
    id: 1,
    title: 'Gratis cuci',
    description: 'Untuk servis besar',
    starts_on: null,
    ends_on: null,
    status: 'active',
    products: [],
  },
];

const mountPage = () =>
  mount(KnowledgePromotionsPage, {
    props: { agent: { id: 7, timezone: 'Asia/Jakarta' } },
    global: {
      plugins: [i18n],
      directives: { tooltip: {} },
      stubs: {
        Button: true,
        Checkbox: true,
        Input: true,
        Icon: true,
        Spinner: true,
        TabBar: true,
        ConfirmDeleteDialog: {
          name: 'ConfirmDeleteDialog',
          template: '<div />',
          methods: { open() {}, close() {} },
        },
        PromotionFormDialog: true,
      },
    },
  });

describe('KnowledgePromotionsPage', () => {
  beforeEach(() => {
    AiAgentKnowledgeAPI.getPromotions.mockResolvedValue({
      data: { payload: PROMOTIONS },
    });
  });

  it('shows each promotion with its status, its period as calendar days, and the products it applies to', async () => {
    const wrapper = mountPage();
    await flushPromises();

    // The text of each span without spans inside it, in order.
    const rows = wrapper.findAll('li').map(row =>
      row
        .findAll('span')
        .filter(span => !span.find('span').exists())
        .map(span => span.text())
    );
    expect(rows).toEqual([
      [
        'Diskon November',
        'Active',
        'Stabill Rp80.000',
        'Applies to: Stabill, Oli Mesin',
        'Nov 1, 2026 to Nov 30, 2026',
      ],
      [
        'Akhir tahun',
        'Scheduled',
        'Diskon 10%',
        'From Dec 20, 2026, no end date',
      ],
      ['Gratis cuci', 'Active', 'Untuk servis besar', 'No end date'],
    ]);
    expect(
      wrapper.findComponent({ name: 'PromotionFormDialog' }).props()
    ).toMatchObject({ agentId: 7, timezone: 'Asia/Jakarta' });
  });

  it('loads the promotions of the status tab', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(AiAgentKnowledgeAPI.getPromotions).toHaveBeenLastCalledWith(7, {
      query: '',
      status: '',
    });
    expect(
      wrapper
        .findComponent({ name: 'TabBar' })
        .props('tabs')
        .map(tab => tab.label)
    ).toEqual(['All', 'Active', 'Scheduled', 'Archived']);

    wrapper
      .findComponent({ name: 'TabBar' })
      .vm.$emit('tabChanged', { value: 'archived' });
    await flushPromises();

    expect(AiAgentKnowledgeAPI.getPromotions).toHaveBeenLastCalledWith(7, {
      query: '',
      status: 'archived',
    });
  });

  it('deletes the selected promotions together', async () => {
    AiAgentKnowledgeAPI.bulkDeletePromotions.mockResolvedValue({});
    const wrapper = mountPage();
    await flushPromises();

    const [selectAll] = wrapper.findAllComponents({ name: 'Checkbox' });
    selectAll.vm.$emit('update:modelValue', true);
    await flushPromises();
    wrapper
      .findAllComponents({ name: 'Button' })
      .find(button => button.props('color') === 'ruby')
      .vm.$emit('click');
    wrapper.findComponent({ name: 'ConfirmDeleteDialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.bulkDeletePromotions).toHaveBeenCalledWith(
      7,
      [3, 2, 1]
    );
    expect(wrapper.emitted('knowledgeChanged')).toHaveLength(1);
  });
});
