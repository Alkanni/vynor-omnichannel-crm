<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const getRecord = useMapGetter('aiAgents/getRecord');

const isNotFound = ref(false);

const agentId = computed(() => Number(route.params.agentId));
const agent = computed(() => getRecord.value(agentId.value));

const tabs = computed(() => [
  { label: t('AI_AGENTS.DETAIL.TABS.GENERAL'), value: 'ai_agents_general' },
  {
    label: t('AI_AGENTS.DETAIL.TABS.KNOWLEDGE_SOURCES'),
    value: 'ai_agents_knowledge',
  },
  {
    label: t('AI_AGENTS.DETAIL.TABS.INTEGRATIONS'),
    value: 'ai_agents_integrations',
  },
]);
const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => route.matched.some(r => r.name === tab.value))
);

const changeTab = tab => {
  router.push({ name: tab.value, params: route.params });
};

const backToList = () => {
  router.push({
    name: 'ai_agents_index',
    params: { accountId: route.params.accountId },
  });
};

const fetchAgent = async () => {
  isNotFound.value = false;
  try {
    await store.dispatch('aiAgents/show', agentId.value);
  } catch {
    isNotFound.value = true;
  }
};

watch(agentId, fetchAgent, { immediate: true });
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="flex flex-col items-center gap-4 px-6 pt-5 pb-4">
      <div class="relative flex items-center justify-center w-full min-h-8">
        <Button
          :label="t('AI_AGENTS.DETAIL.BACK')"
          icon="i-lucide-arrow-left"
          color="slate"
          variant="faded"
          size="sm"
          class="absolute start-0"
          @click="backToList"
        />
        <h1 class="px-28 truncate text-heading-1 text-n-slate-12">
          {{ agent.name }}
        </h1>
      </div>
      <TabBar
        v-if="!isNotFound"
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="changeTab"
      />
    </header>

    <p
      v-if="isNotFound"
      class="px-6 py-10 text-center text-body-main text-n-slate-11"
    >
      {{ t('AI_AGENTS.DETAIL.NOT_FOUND') }}
    </p>
    <div v-else-if="agent.id" class="flex-1 min-h-0">
      <router-view :agent="agent" />
    </div>
    <div v-else class="flex justify-center py-10">
      <Spinner />
    </div>
  </section>
</template>
