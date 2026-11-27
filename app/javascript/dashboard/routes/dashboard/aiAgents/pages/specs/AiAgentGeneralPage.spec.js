import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import aiAgents from 'dashboard/i18n/locale/en/aiAgents.json';
import AiAgentGeneralPage from '../AiAgentGeneralPage.vue';
import BookingFieldsEditor from '../../components/BookingFieldsEditor.vue';

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
  booking_fields: [
    {
      name: 'Plate number',
      description: '',
      type: 'text',
      options: [],
      required: false,
    },
  ],
  booking_services: [],
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

describe('AiAgentGeneralPage booking fields and services', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockImplementation((action, payload) =>
      Promise.resolve(
        action === 'aiAgents/update' ? { ...agent, ...payload } : agent
      )
    );
  });

  it('saves the fields of the editor and the services, and shows them as saved', async () => {
    const fields = [
      ...agent.booking_fields,
      {
        name: 'Vehicle',
        description: 'Car or motorbike',
        type: 'choice',
        options: ['Car', 'Motorbike'],
        required: true,
      },
    ];
    const wrapper = mountPage();
    await flushPromises();

    const editor = wrapper.findComponent(BookingFieldsEditor);
    expect(editor.props('modelValue')).toEqual(agent.booking_fields);
    editor.vm.$emit('update:modelValue', fields);
    wrapper
      .findComponent({ name: 'TagInput' })
      .vm.$emit('update:modelValue', ['Regular service']);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'aiAgents/update',
      expect.objectContaining({
        booking_fields: fields,
        booking_services: ['Regular service'],
      })
    );
    expect(
      wrapper.findComponent(BookingFieldsEditor).props('modelValue')
    ).toEqual(fields);
    expect(
      wrapper.findComponent({ name: 'TagInput' }).props('modelValue')
    ).toEqual(['Regular service']);
  });
});

describe('AiAgentGeneralPage promotion offers', () => {
  const strictAgent = {
    scope_mode: 'strict',
    business_description: 'Bengkel mobil',
    allowed_topics: 'Servis',
    off_topic_message: 'Maaf.',
    clarification_message: 'Yang mana?',
    knowledge_gap_message: 'Belum ada info.',
  };
  const offersToggle = wrapper =>
    wrapper
      .findAllComponents({ name: 'ToggleField' })
      .find(toggle => toggle.props('title') === 'Offer Promotions Proactively');
  const submit = async wrapper => {
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    return dispatch.mock.calls.find(
      ([action]) => action === 'aiAgents/update'
    )[1];
  };

  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockImplementation((action, payload) =>
      Promise.resolve(
        action === 'aiAgents/update' ? { ...agent, ...payload } : agent
      )
    );
  });

  it('is offered for a strict agent only and saves the choice', async () => {
    expect(offersToggle(mountPage())).toBeUndefined();

    const wrapper = mountPage({
      ...strictAgent,
      promotion_offers_enabled: false,
    });
    await flushPromises();
    offersToggle(wrapper).vm.$emit('update:modelValue', true);

    expect(await submit(wrapper)).toMatchObject({
      promotion_offers_enabled: true,
    });
  });

  it('turns off with web search when Strict is turned off', async () => {
    const wrapper = mountPage({
      ...strictAgent,
      web_search_enabled: true,
      promotion_offers_enabled: true,
    });
    await flushPromises();
    expect(offersToggle(wrapper).props('modelValue')).toBe(true);

    wrapper
      .findAllComponents({ name: 'ComboBox' })
      .find(comboBox => comboBox.props('modelValue') === 'strict')
      .vm.$emit('update:modelValue', 'off');
    await flushPromises();

    expect(offersToggle(wrapper)).toBeUndefined();
    expect(await submit(wrapper)).toMatchObject({
      scope_mode: 'off',
      web_search_enabled: false,
      promotion_offers_enabled: false,
    });
  });
});
