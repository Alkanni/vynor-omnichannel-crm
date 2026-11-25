import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import aiAgents from 'dashboard/i18n/locale/en/aiAgents.json';
import AiAgentGeneralPage from '../AiAgentGeneralPage.vue';

const dispatch = vi.fn();

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return { useMapGetter: () => ref([]) };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/api/aiAgents', () => ({
  default: {
    getModels: vi.fn(() => Promise.resolve({ data: { models: [] } })),
    train: vi.fn(),
  },
}));

const STARTER_TEMPLATE = [
  'Booking summary',
  'Name: {{booking.customer_name}}',
  'Service: {{booking.service}}',
  'Date: {{booking.date}}',
  'Time: {{booking.time}}',
  '{% if booking.extra_fields != blank %}{{booking.extra_fields}}\n{% endif %}' +
    '{% if booking.notes != blank %}Notes: {{booking.notes}}\n{% endif %}',
  'Reply "Yes" if this is correct.',
].join('\n');

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: aiAgents },
});

const agent = {
  id: 7,
  name: 'CS Bengkel',
  llm_configured: true,
  inbox_ids: [],
  allowed_label_ids: [],
  model: 'gpt-4.1-mini',
  temperature: 'precise',
  timezone: 'Asia/Jakarta',
  scope_mode: 'off',
  booking_enabled: true,
  booking_conditions: 'Saat customer ingin datang ke bengkel.',
  booking_label_id: null,
  booking_fields: ['Plate number'],
  booking_summary_template: null,
};

const mountPage = (overrides = {}) =>
  mount(AiAgentGeneralPage, {
    props: { agent: { ...agent, ...overrides } },
    global: {
      plugins: [i18n],
      stubs: {
        AiAgentPlayground: true,
        Banner: true,
        ComboBox: true,
        Input: true,
        TagInput: true,
        TagMultiSelectComboBox: true,
        ToggleField: true,
        CollapsiblePanel: { template: '<section><slot /></section>' },
        Button: {
          props: ['label'],
          template: '<button v-bind="$attrs">{{ label }}</button>',
        },
        TextArea: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<textarea :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

const starterButton = wrapper =>
  wrapper
    .findAll('button')
    .find(button => button.text() === 'Fill in a starter template');

describe('AiAgentGeneralPage booking summary template', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockImplementation((action, payload) =>
      Promise.resolve(
        action === 'aiAgents/update' ? { ...agent, ...payload } : agent
      )
    );
  });

  it('fills an empty template with the starter and saves it', async () => {
    const wrapper = mountPage();
    await flushPromises();

    await starterButton(wrapper).trigger('click');

    expect(
      wrapper.find('#ai-agent-booking-summary-template').element.value
    ).toBe(STARTER_TEMPLATE);
    expect(starterButton(wrapper)).toBeUndefined();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'aiAgents/update',
      expect.objectContaining({
        id: 7,
        booking_summary_template: STARTER_TEMPLATE,
      })
    );
  });

  it('shows a saved template without the starter, and the variables a summary can use', async () => {
    const wrapper = mountPage({
      booking_summary_template: 'Ringkasan {{booking.service}}',
    });
    await flushPromises();

    expect(
      wrapper.find('#ai-agent-booking-summary-template').element.value
    ).toBe('Ringkasan {{booking.service}}');
    expect(starterButton(wrapper)).toBeUndefined();
    expect(wrapper.text()).toContain(
      'You can use {{booking.customer_name}}, {{booking.service}}, {{booking.date}}, {{booking.time}}, ' +
        '{{booking.notes}}, {{booking.extra_fields}}, and {{booking.details["Plate number"]}} for one extra field.'
    );
  });
});
