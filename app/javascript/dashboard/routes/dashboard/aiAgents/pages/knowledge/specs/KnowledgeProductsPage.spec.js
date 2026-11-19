import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import KnowledgeProductsPage from '../KnowledgeProductsPage.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: { getProducts: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      AI_AGENTS: {
        KNOWLEDGE: {
          PRODUCT: {
            WEIGHT: 'Weight:',
            WEIGHT_VALUE: '{weight} Grams',
            STOCK: 'Stock:',
            PRICE: 'Price:',
          },
        },
      },
    },
  },
});

const mountPage = () =>
  mount(KnowledgeProductsPage, {
    props: { agent: { id: 7 } },
    global: {
      plugins: [i18n],
      directives: { tooltip: {} },
      stubs: {
        Button: true,
        Checkbox: true,
        Input: true,
        Icon: true,
        Spinner: true,
        ConfirmDeleteDialog: true,
        ProductFormDialog: true,
      },
    },
  });

describe('KnowledgeProductsPage', () => {
  it('shows the recorded numbers, 0 too, with the price in the currency of the list, and hides blank ones', async () => {
    AiAgentKnowledgeAPI.getProducts.mockResolvedValue({
      data: {
        currency: 'IDR',
        payload: [
          { id: 1, name: 'Roti Sobek', price: 25000, weight: 400, stock: 0 },
          { id: 2, name: 'Konsultasi', price: null, weight: null, stock: null },
        ],
      },
    });

    const wrapper = mountPage();
    await flushPromises();

    const [full, blank] = wrapper.findAll('dl');
    expect(full.findAll('dt').map(item => item.text())).toEqual([
      'Weight:',
      'Stock:',
      'Price:',
    ]);
    expect(
      full.findAll('dd').map(item => item.text().replace(/\s/g, ' '))
    ).toEqual(['400 Grams', '0', 'IDR 25,000']);
    expect(blank.findAll('dt')).toHaveLength(0);
    expect(
      wrapper.findComponent({ name: 'ProductFormDialog' }).props()
    ).toMatchObject({ currency: 'IDR' });
  });
});
