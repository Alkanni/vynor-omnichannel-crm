<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { OnClickOutside } from '@vueuse/components';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store.js';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';

import ConversationBasicFilter from './widgets/conversation/ConversationBasicFilter.vue';
import SwitchLayout from 'dashboard/routes/dashboard/conversation/search/SwitchLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  contactFilter: { type: Object, default: null },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  activeStatus: { type: String, required: true },
  showStatusFilter: { type: Boolean, default: true },
  activeAgentId: { type: Number, default: null },
  showUnreadOnly: { type: Boolean, default: false },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'basicFilterChange',
  'filtersModal',
  'agentFilterChange',
  'toggleUnread',
]);

const { t } = useI18n();
const router = useRouter();
const { uiSettings, updateUISettings } = useUISettings();

const agents = useMapGetter('agents/getAgents');
const [showAgentMenu, toggleAgentMenu] = useToggle();

const activeAgentLabel = computed(
  () =>
    agents.value.find(agent => agent.id === props.activeAgentId)?.name ||
    t('CHAT_LIST.AGENT_FILTER.ALL_AGENTS')
);

const agentMenuItems = computed(() => [
  {
    label: t('CHAT_LIST.AGENT_FILTER.ALL_AGENTS'),
    value: null,
    action: 'filter',
    isSelected: !props.activeAgentId,
  },
  ...agents.value.map(agent => ({
    label: agent.name,
    value: agent.id,
    action: 'filter',
    thumbnail: { name: agent.name, src: agent.thumbnail },
    isSelected: props.activeAgentId === agent.id,
  })),
]);

const onAgentSelect = ({ value }) => {
  toggleAgentMenu(false);
  if (value !== props.activeAgentId) emit('agentFilterChange', value);
};

const openSearch = () => {
  router.push({ name: 'search', params: { tab: 'conversations' } });
};

const onBasicFilterChange = (value, type) => {
  emit('basicFilterChange', value, type);
};

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

// While filters narrow the list, the header names it and the back button exits.
const showFilterScope = computed(
  () => props.hasAppliedFilters && !props.hasActiveFolders
);

// The contact scope is set from the contact panel; it is exited, not edited.
const isContactScoped = computed(
  () => showFilterScope.value && !!props.contactFilter
);

const title = computed(
  () => (isContactScoped.value && props.contactFilter.name) || props.pageTitle
);

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-3 h-[3.25rem]"
    :class="{
      'border-b border-n-strong': hasAppliedFiltersOrActiveFolders,
    }"
  >
    <div class="flex items-center justify-center min-w-0">
      <NextButton
        v-if="showFilterScope"
        v-tooltip.right="$t('FILTER.CLEAR_BUTTON_LABEL')"
        :aria-label="$t('FILTER.CLEAR_BUTTON_LABEL')"
        icon="i-lucide-chevron-left"
        class="shrink-0 -ms-2 !h-6 !w-6 me-1"
        slate
        sm
        ghost
        @click="emit('resetFilters')"
      />
      <h1
        v-if="title"
        class="text-base font-medium truncate text-n-slate-12"
        :title="title"
      >
        {{ title }}
      </h1>
      <OnClickOutside
        v-if="!hasAppliedFiltersOrActiveFolders"
        class="relative min-w-0"
        :class="{ 'ms-1': title }"
        @trigger="toggleAgentMenu(false)"
      >
        <NextButton
          v-tooltip.top-start="$t('CHAT_LIST.AGENT_FILTER.TOOLTIP')"
          variant="outline"
          color="slate"
          size="sm"
          class="max-w-36 !h-7 !px-2"
          @click="toggleAgentMenu()"
        >
          <span class="truncate">{{ activeAgentLabel }}</span>
          <Icon icon="i-lucide-chevron-down" class="text-n-slate-11 shrink-0" />
        </NextButton>
        <DropdownMenu
          v-if="showAgentMenu"
          :menu-items="agentMenuItems"
          show-search
          class="mt-1 start-0 top-full w-56 max-h-72"
          @action="onAgentSelect"
        />
      </OnClickOutside>
      <span
        v-if="
          allCount > 0 && hasAppliedFiltersOrActiveFolders && !isListLoading
        "
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
        :title="allCount"
      >
        {{ formattedAllCount }}
      </span>
      <span
        v-if="!hasAppliedFiltersOrActiveFolders"
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
      >
        {{ $t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus}.TEXT`) }}
      </span>
    </div>
    <div class="flex items-center gap-1">
      <NextButton
        v-tooltip.top-end="$t('CHAT_LIST.SEARCH_TOOLTIP')"
        :aria-label="$t('CHAT_LIST.SEARCH_TOOLTIP')"
        icon="i-lucide-search"
        slate
        xs
        faded
        @click="openSearch"
      />
      <NextButton
        v-if="!hasAppliedFiltersOrActiveFolders"
        v-tooltip.top-end="$t('CHAT_LIST.UNREAD_FILTER_TOOLTIP')"
        :aria-label="$t('CHAT_LIST.UNREAD_FILTER_TOOLTIP')"
        :aria-pressed="showUnreadOnly"
        icon="i-lucide-message-square-dot"
        :color="showUnreadOnly ? 'blue' : 'slate'"
        xs
        faded
        @click="emit('toggleUnread')"
      />
      <template v-if="hasAppliedFilters && !hasActiveFolders">
        <div class="relative">
          <NextButton
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
            icon="i-lucide-save"
            slate
            xs
            faded
            @click="emit('addFolders')"
          />
          <div
            id="saveFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
      </template>
      <template v-if="hasActiveFolders">
        <div class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
            icon="i-lucide-pen-line"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          @click="emit('deleteFolders')"
        />
      </template>
      <div v-else-if="!isContactScoped" class="relative">
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.right="$t('FILTER.TOOLTIP_LABEL')"
          icon="i-lucide-list-filter"
          slate
          xs
          faded
          @click="emit('filtersModal')"
        />
        <div
          id="conversationFilterTeleportTarget"
          class="absolute z-50 mt-2"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        />
      </div>
      <ConversationBasicFilter
        v-if="!isContactScoped"
        :is-on-expanded-layout="isOnExpandedLayout"
        :show-status-filter="
          showStatusFilter && !hasAppliedFiltersOrActiveFolders
        "
        @change-filter="onBasicFilterChange"
      />
      <SwitchLayout
        :is-on-expanded-layout="isOnExpandedLayout"
        @toggle="toggleConversationLayout"
      />
    </div>
  </div>
</template>
