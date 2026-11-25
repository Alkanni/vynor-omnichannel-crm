import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import PromotionFormDialog from '../PromotionFormDialog.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    getProducts: vi.fn(),
    createPromotion: vi.fn(),
    updatePromotion: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// The labels do not matter here, so missing keys stay quiet.
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
  missingWarn: false,
});

const fieldStub = tag => ({
  props: ['modelValue', 'disabled'],
  emits: ['update:modelValue'],
  template: `<${tag} :value="modelValue" :disabled="disabled" @input="$emit('update:modelValue', $event.target.value)" />`,
});

const mountDialog = () =>
  mount(PromotionFormDialog, {
    props: { agentId: 7, timezone: 'Asia/Jakarta' },
    global: {
      plugins: [i18n],
      stubs: {
        Dialog: {
          name: 'Dialog',
          props: ['disableConfirmButton'],
          emits: ['confirm'],
          template:
            '<div><slot /><button data-test="confirm" :disabled="disableConfirmButton" @click="$emit(\'confirm\')" /></div>',
          methods: { open() {}, close() {} },
        },
        Input: fieldStub('input'),
        TextArea: fieldStub('textarea'),
        Checkbox: {
          name: 'Checkbox',
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input type="checkbox" :checked="modelValue" @change="$emit(\'update:modelValue\', $event.target.checked)" />',
        },
        TagMultiSelectComboBox: true,
      },
    },
  });

describe('PromotionFormDialog', () => {
  beforeEach(() => {
    AiAgentKnowledgeAPI.getProducts.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'Stabill' },
          { id: 2, name: 'Oli Mesin' },
        ],
      },
    });
  });

  it('asks for an end date or No end date before adding a promotion, and sends a blank end date for No end date', async () => {
    AiAgentKnowledgeAPI.createPromotion.mockResolvedValue({});
    const wrapper = mountDialog();
    wrapper.vm.open();
    await flushPromises();

    const confirm = wrapper.find('[data-test="confirm"]');
    await wrapper.find('#ai-agent-promotion-title').setValue(' Diskon ');
    await wrapper
      .find('#ai-agent-promotion-description')
      .setValue('Stabill Rp80.000');
    expect(confirm.element.disabled).toBe(true);

    await wrapper.find('#ai-agent-promotion-ends-on').setValue('2026-11-30');
    expect(confirm.element.disabled).toBe(false);

    await wrapper.find('input[type="checkbox"]').setValue(true);
    expect(wrapper.find('#ai-agent-promotion-ends-on').element.disabled).toBe(
      true
    );
    await confirm.trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.createPromotion).toHaveBeenCalledWith(7, {
      title: 'Diskon',
      description: 'Stabill Rp80.000',
      starts_on: '',
      ends_on: '',
      product_ids: [],
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('edits a promotion with its dates and products, offering the products of the agent', async () => {
    AiAgentKnowledgeAPI.updatePromotion.mockResolvedValue({});
    const wrapper = mountDialog();
    wrapper.vm.open({
      id: 3,
      title: 'Diskon',
      description: 'Stabill Rp80.000',
      starts_on: '2026-11-01',
      ends_on: '2026-11-30',
      products: [{ id: 1, name: 'Stabill' }],
    });
    await flushPromises();

    const products = wrapper.findComponent({ name: 'TagMultiSelectComboBox' });
    expect(products.props('options')).toEqual([
      { value: 1, label: 'Stabill' },
      { value: 2, label: 'Oli Mesin' },
    ]);
    expect(products.props('modelValue')).toEqual([1]);
    products.vm.$emit('update:modelValue', [1, 2]);
    await wrapper.find('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.updatePromotion).toHaveBeenCalledWith(7, 3, {
      title: 'Diskon',
      description: 'Stabill Rp80.000',
      starts_on: '2026-11-01',
      ends_on: '2026-11-30',
      product_ids: [1, 2],
    });
  });
});
