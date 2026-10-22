<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiAgentCard from '../components/AiAgentCard.vue';
import CreateAiAgentDialog from '../components/CreateAiAgentDialog.vue';
import DeleteAiAgentDialog from '../components/DeleteAiAgentDialog.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const aiAgents = useMapGetter('aiAgents/getRecords');
const uiFlags = useMapGetter('aiAgents/getUIFlags');

const searchQuery = ref('');
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);

const filteredAgents = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return aiAgents.value;

  return aiAgents.value.filter(agent =>
    agent.name.toLowerCase().includes(query)
  );
});

const isInitialLoading = computed(
  () => uiFlags.value.fetchingList && !aiAgents.value.length
);

const openSettings = agent => {
  router.push({
    name: 'ai_agents_general',
    params: { accountId: route.params.accountId, agentId: agent.id },
  });
};

const duplicateAgent = async agent => {
  try {
    await store.dispatch('aiAgents/duplicate', agent.id);
    useAlert(t('AI_AGENTS.DUPLICATE.SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('AI_AGENTS.DUPLICATE.ERROR'));
  }
};

onMounted(() => {
  store.dispatch('aiAgents/get');
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full gap-8 px-6 py-10 mx-auto max-w-[71rem] items-center"
    >
      <header class="flex flex-col items-center gap-2 text-center max-w-xl">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('AI_AGENTS.HEADER') }}
        </h1>
        <p class="text-body-para text-n-slate-11">
          {{ t('AI_AGENTS.DESCRIPTION') }}
        </p>
      </header>

      <Input
        v-model="searchQuery"
        type="search"
        :placeholder="t('AI_AGENTS.SEARCH_PLACEHOLDER')"
        :custom-input-class="['ltr:!pl-8 rtl:!pr-8']"
        class="w-full max-w-md"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>

      <div
        v-if="isInitialLoading"
        class="flex items-center gap-2 py-10 text-n-slate-11"
      >
        <Spinner />
        <span class="text-body-main">{{ t('AI_AGENTS.LOADING') }}</span>
      </div>

      <div
        v-else
        class="grid w-full gap-4 grid-cols-[repeat(auto-fill,minmax(15rem,1fr))]"
      >
        <AiAgentCard
          v-for="agent in filteredAgents"
          :key="agent.id"
          :agent="agent"
          @settings="openSettings"
          @duplicate="duplicateAgent"
          @delete="deleteDialogRef.open($event)"
        />
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-3 px-5 py-6 text-white transition-colors rounded-xl min-h-48 bg-n-brand hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          @click="createDialogRef.open()"
        >
          <span
            class="flex items-center justify-center bg-white rounded-full size-11 text-n-brand"
          >
            <Icon icon="i-lucide-plus" class="size-5" />
          </span>
          <span class="text-heading-2">{{ t('AI_AGENTS.CREATE.CARD') }}</span>
        </button>
      </div>

      <p
        v-if="searchQuery && !filteredAgents.length && !isInitialLoading"
        class="text-body-main text-n-slate-11"
      >
        {{ t('AI_AGENTS.NO_RESULTS') }}
      </p>
    </div>

    <CreateAiAgentDialog ref="createDialogRef" @created="openSettings" />
    <DeleteAiAgentDialog ref="deleteDialogRef" />
  </section>
</template>
