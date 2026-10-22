<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';

import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import KnowledgeStatsPanel from '../components/KnowledgeStatsPanel.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const stats = ref({});

const tabs = computed(() => [
  {
    label: t('AI_AGENTS.KNOWLEDGE.TABS.TEXT'),
    value: 'ai_agents_knowledge_text',
  },
  { label: t('AI_AGENTS.KNOWLEDGE.TABS.QA'), value: 'ai_agents_knowledge_qa' },
  {
    label: t('AI_AGENTS.KNOWLEDGE.TABS.PRODUCT'),
    value: 'ai_agents_knowledge_products',
  },
]);
const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.value === route.name)
);

const changeTab = tab => {
  router.push({ name: tab.value, params: route.params });
};

const fetchStats = async () => {
  const { data } = await AiAgentKnowledgeAPI.getStats(props.agent.id);
  stats.value = data;
};

watch(() => props.agent.id, fetchStats, { immediate: true });
</script>

<template>
  <div class="h-full overflow-y-auto">
    <div class="flex flex-col w-full gap-5 px-6 pt-2 pb-10 mx-auto max-w-6xl">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="changeTab"
      />
      <div class="flex flex-col-reverse items-start gap-6 lg:flex-row">
        <div class="flex-1 w-full min-w-0">
          <router-view :agent="agent" @knowledge-changed="fetchStats" />
        </div>
        <KnowledgeStatsPanel
          :stats="stats"
          class="w-full lg:w-64 shrink-0 lg:sticky lg:top-0"
        />
      </div>
    </div>
  </div>
</template>
