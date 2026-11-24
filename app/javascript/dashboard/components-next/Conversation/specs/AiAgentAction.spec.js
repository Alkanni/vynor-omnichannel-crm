import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import AiAgentAction from '../AiAgentAction.vue';

const dispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const aiAgent = { id: 5, name: 'Vynor Testing V2' };

const mountAction = conversation =>
  mount(AiAgentAction, {
    props: { conversation: { id: 42, ...conversation } },
    global: { directives: { onClickaway: {} }, stubs: { DropdownMenu: true } },
  });

const openMenu = async wrapper => {
  await wrapper.find('button').trigger('click');
  return wrapper.findComponent(DropdownMenu);
};

describe('AiAgentAction', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('stays hidden for inboxes without an AI agent', () => {
    const wrapper = mountAction({
      status: 'pending',
      meta: { ai_agent: null },
    });

    expect(wrapper.findComponent(Button).exists()).toBe(false);
  });

  it.each(['resolved', 'snoozed'])(
    'stays hidden for %s conversations',
    status => {
      const wrapper = mountAction({
        status,
        meta: { ai_agent: { ...aiAgent, active: false } },
      });

      expect(wrapper.findComponent(Button).exists()).toBe(false);
    }
  );

  it('shows the AI agent answering a pending conversation and lets the agent take it over', async () => {
    const wrapper = mountAction({
      status: 'pending',
      meta: { ai_agent: { ...aiAgent, active: true } },
    });

    expect(wrapper.findComponent(Button).props()).toMatchObject({
      label: 'CONVERSATION.AI_AGENT_ACTION.ACTIVE',
      icon: 'i-lucide-bot',
      color: 'teal',
    });

    const menu = await openMenu(wrapper);
    expect(menu.props('menuItems')).toEqual([
      expect.objectContaining({
        label: 'CONVERSATION.AI_AGENT_ACTION.TAKE_OVER',
        action: 'open',
      }),
    ]);

    menu.vm.$emit('action', { action: 'open' });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('toggleStatus', {
      conversationId: 42,
      status: 'open',
    });
    expect(useAlert).toHaveBeenCalledWith('CONVERSATION.CHANGE_STATUS');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  });

  it('shows the AI agent off for an open conversation and lets the agent hand it back', async () => {
    const wrapper = mountAction({
      status: 'open',
      meta: { ai_agent: { ...aiAgent, active: false } },
    });

    expect(wrapper.findComponent(Button).props()).toMatchObject({
      label: 'CONVERSATION.AI_AGENT_ACTION.INACTIVE',
      icon: 'i-lucide-bot-off',
      color: 'slate',
    });

    const menu = await openMenu(wrapper);
    expect(menu.props('menuItems')).toEqual([
      expect.objectContaining({
        label: 'CONVERSATION.AI_AGENT_ACTION.HAND_OVER',
        action: 'pending',
      }),
    ]);

    menu.vm.$emit('action', { action: 'pending' });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('toggleStatus', {
      conversationId: 42,
      status: 'pending',
    });
  });

  it('offers a take-over while the AI keeps answering an open conversation after a handoff', async () => {
    const wrapper = mountAction({
      status: 'open',
      meta: { ai_agent: { ...aiAgent, active: true } },
    });

    expect(wrapper.findComponent(Button).props('label')).toBe(
      'CONVERSATION.AI_AGENT_ACTION.ACTIVE'
    );
    const menu = await openMenu(wrapper);
    expect(menu.props('menuItems')[0].action).toBe('open');
  });
});
