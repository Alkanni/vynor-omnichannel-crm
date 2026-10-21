import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import WhatsappAppSecret from '../WhatsappAppSecret.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const updateInbox = vi.fn();

const mountComponent = providerConfig =>
  mount(WhatsappAppSecret, {
    props: {
      inbox: {
        id: 7,
        provider: 'whatsapp_cloud',
        provider_config: providerConfig,
      },
    },
    global: {
      plugins: [
        createStore({ actions: { 'inboxes/updateInbox': updateInbox } }),
      ],
      stubs: {
        SettingsFieldSection: { template: '<section><slot /></section>' },
        NextButton: {
          template: '<button @click="$emit(\'click\')"><slot /></button>',
        },
        Icon: true,
        'woot-input': {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

describe('WhatsappAppSecret', () => {
  beforeEach(() => updateInbox.mockClear());

  it('warns when no app secret is configured', () => {
    const wrapper = mountComponent({ api_key: 'token' });

    expect(wrapper.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_NOT_CONFIGURED'
    );
  });

  it('shows the configured state without rendering the secret', () => {
    const wrapper = mountComponent({ api_key: 'token', app_secret: 'stored' });

    expect(wrapper.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_CONFIGURED'
    );
    expect(wrapper.html()).not.toContain('stored');
  });

  it('saves the app secret while keeping the existing provider config', async () => {
    const wrapper = mountComponent({
      api_key: 'token',
      source: 'manual_setup_v2',
    });

    await wrapper.find('input').setValue(' new-secret ');
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(updateInbox).toHaveBeenCalledWith(expect.anything(), {
      id: 7,
      formData: false,
      channel: {
        provider_config: {
          api_key: 'token',
          source: 'manual_setup_v2',
          app_secret: 'new-secret',
        },
      },
    });
  });
});
