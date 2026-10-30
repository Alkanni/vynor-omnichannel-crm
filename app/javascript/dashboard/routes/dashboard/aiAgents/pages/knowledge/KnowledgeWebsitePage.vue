<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';
import SourceStatusBadge from '../../components/SourceStatusBadge.vue';
import { useProcessingPoll } from '../../composables/useProcessingPoll';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged', 'viewChunks']);

const SOURCE_TYPE = 'website';
const MODES = { BATCH: 'batch', SINGLE: 'single' };

const { t, locale } = useI18n();

const mode = ref(MODES.BATCH);
const url = ref('');
const collectedLinks = ref([]);
const selectedLinks = ref([]);
const isCollecting = ref(false);
const isAdding = ref(false);
const sources = ref([]);
const isLoading = ref(true);
const searchQuery = ref('');
const selectedIds = ref([]);
const deletingIds = ref([]);
const isDeleting = ref(false);
const deleteDialogRef = ref(null);

const modeTabs = computed(() => [
  { label: t('AI_AGENTS.KNOWLEDGE.WEBSITE.MODES.BATCH'), value: MODES.BATCH },
  { label: t('AI_AGENTS.KNOWLEDGE.WEBSITE.MODES.SINGLE'), value: MODES.SINGLE },
]);
const modeIndex = computed(() =>
  modeTabs.value.findIndex(tab => tab.value === mode.value)
);
const filteredSources = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return sources.value;

  return sources.value.filter(source =>
    [source.title, source.external_url].some(value =>
      value.toLowerCase().includes(query)
    )
  );
});
const allSourcesSelected = computed(
  () =>
    filteredSources.value.length > 0 &&
    filteredSources.value.every(source => selectedIds.value.includes(source.id))
);
const allLinksSelected = computed(
  () =>
    collectedLinks.value.length > 0 &&
    selectedLinks.value.length === collectedLinks.value.length
);

const formatNumber = value => new Intl.NumberFormat(locale.value).format(value);

const fetchSources = async () => {
  try {
    const { data } = await AiAgentKnowledgeAPI.getSources(
      props.agent.id,
      SOURCE_TYPE
    );
    sources.value = data.payload;
    const ids = new Set(data.payload.map(source => source.id));
    selectedIds.value = selectedIds.value.filter(id => ids.has(id));
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const { hasInProgress } = useProcessingPoll(sources, fetchSources);

const alertError = (error, fallback) => {
  const message = parseAPIErrorResponse(error);
  useAlert(typeof message === 'string' ? message : fallback);
};

const changeMode = tab => {
  mode.value = tab.value;
  url.value = '';
  collectedLinks.value = [];
  selectedLinks.value = [];
};

const collectLinks = async () => {
  isCollecting.value = true;
  try {
    const { data } = await AiAgentKnowledgeAPI.collectLinks(
      props.agent.id,
      url.value.trim()
    );
    collectedLinks.value = data.links;
    selectedLinks.value = [...data.links];
  } catch (error) {
    alertError(error, t('AI_AGENTS.KNOWLEDGE.WEBSITE.COLLECT_ERROR'));
  } finally {
    isCollecting.value = false;
  }
};

const addLinks = async urls => {
  isAdding.value = true;
  try {
    await AiAgentKnowledgeAPI.addWebsites(props.agent.id, urls);
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.ADD_SUCCESS'));
    url.value = '';
    collectedLinks.value = [];
    selectedLinks.value = [];
    await fetchSources();
    emit('knowledgeChanged');
  } catch (error) {
    alertError(error, t('AI_AGENTS.KNOWLEDGE.WEBSITE.ADD_ERROR'));
  } finally {
    isAdding.value = false;
  }
};

const toggleLink = (link, checked) => {
  selectedLinks.value = checked
    ? [...selectedLinks.value, link]
    : selectedLinks.value.filter(item => item !== link);
};

const toggleAllSources = checked => {
  selectedIds.value = checked
    ? filteredSources.value.map(source => source.id)
    : [];
};

const toggleSource = (id, checked) => {
  selectedIds.value = checked
    ? [...selectedIds.value, id]
    : selectedIds.value.filter(item => item !== id);
};

const resync = async source => {
  try {
    await AiAgentKnowledgeAPI.resyncSource(props.agent.id, source.id);
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.RESYNC_SUCCESS'));
    await fetchSources();
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.RESYNC_ERROR'));
  }
};

const openDeleteDialog = ids => {
  deletingIds.value = ids;
  deleteDialogRef.value.open();
};

const deleteSources = async () => {
  isDeleting.value = true;
  try {
    await AiAgentKnowledgeAPI.bulkDeleteSources(
      props.agent.id,
      deletingIds.value
    );
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE_SUCCESS'));
    await fetchSources();
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

watch(hasInProgress, (inProgress, wasInProgress) => {
  if (wasInProgress && !inProgress) emit('knowledgeChanged');
});
watch(
  () => props.agent.id,
  () => {
    isLoading.value = true;
    fetchSources();
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-6">
    <div class="flex flex-col gap-4">
      <header class="flex flex-col gap-1">
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.TITLE') }}
        </h2>
        <p class="text-body-para text-n-slate-11">
          {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.DESCRIPTION') }}
        </p>
      </header>
      <TabBar
        :tabs="modeTabs"
        :initial-active-tab="modeIndex"
        @tab-changed="changeMode"
      />

      <form
        class="flex flex-col gap-2"
        @submit.prevent="
          mode === MODES.BATCH ? collectLinks() : addLinks([url.trim()])
        "
      >
        <label for="ai-agent-website-url" class="text-label text-n-slate-12">
          {{
            mode === MODES.BATCH
              ? t('AI_AGENTS.KNOWLEDGE.WEBSITE.COLLECTOR_LABEL')
              : t('AI_AGENTS.KNOWLEDGE.WEBSITE.SINGLE_LABEL')
          }}
        </label>
        <div class="flex flex-wrap items-start gap-2">
          <Input
            id="ai-agent-website-url"
            v-model="url"
            type="url"
            :placeholder="t('AI_AGENTS.KNOWLEDGE.WEBSITE.URL_PLACEHOLDER')"
            class="flex-1 min-w-56"
          />
          <Button
            type="submit"
            :label="
              mode === MODES.BATCH
                ? t('AI_AGENTS.KNOWLEDGE.WEBSITE.COLLECT')
                : t('AI_AGENTS.KNOWLEDGE.WEBSITE.ADD_LINK')
            "
            :disabled="!url.trim() || isCollecting || isAdding"
            :is-loading="isCollecting || (mode === MODES.SINGLE && isAdding)"
          />
        </div>
        <p
          v-if="mode === MODES.BATCH"
          class="flex items-center gap-2 text-body-main text-n-slate-11"
        >
          <Icon icon="i-lucide-info" class="size-4 shrink-0 text-n-brand" />
          {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.COLLECT_HINT') }}
        </p>
      </form>

      <div
        v-if="collectedLinks.length"
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <label class="flex items-center gap-2 cursor-pointer">
            <Checkbox
              :model-value="allLinksSelected"
              :indeterminate="selectedLinks.length > 0 && !allLinksSelected"
              @update:model-value="
                selectedLinks = $event ? [...collectedLinks] : []
              "
            />
            <span class="text-body-main text-n-slate-12">
              {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.SELECT_ALL') }}
            </span>
            <span class="text-body-main text-n-slate-11">
              {{
                t('AI_AGENTS.KNOWLEDGE.WEBSITE.COLLECTED', {
                  count: collectedLinks.length,
                })
              }}
            </span>
          </label>
          <Button
            :label="
              t('AI_AGENTS.KNOWLEDGE.WEBSITE.TRAIN_SELECTED', {
                count: selectedLinks.length,
              })
            "
            :disabled="!selectedLinks.length || isAdding"
            :is-loading="isAdding"
            @click="addLinks(selectedLinks)"
          />
        </div>
        <ul class="flex flex-col gap-2 overflow-y-auto max-h-72">
          <li
            v-for="link in collectedLinks"
            :key="link"
            class="flex items-center min-w-0 gap-2"
          >
            <Checkbox
              :model-value="selectedLinks.includes(link)"
              @update:model-value="toggleLink(link, $event)"
            />
            <span class="truncate text-body-main text-n-slate-11">{{
              link
            }}</span>
          </li>
        </ul>
      </div>
    </div>

    <div class="flex flex-col gap-4 pt-6 border-t border-n-weak">
      <h2 class="text-heading-2 text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.TRAINED_TITLE') }}
      </h2>
      <div class="flex flex-wrap items-center gap-3">
        <label class="flex items-center gap-2 cursor-pointer shrink-0">
          <Checkbox
            :model-value="allSourcesSelected"
            :indeterminate="selectedIds.length > 0 && !allSourcesSelected"
            :disabled="!filteredSources.length"
            @update:model-value="toggleAllSources"
          />
          <span class="text-body-main text-n-blue-11">
            {{ t('AI_AGENTS.KNOWLEDGE.WEBSITE.SELECT') }}
          </span>
        </label>
        <Input
          v-model="searchQuery"
          type="search"
          :placeholder="t('AI_AGENTS.KNOWLEDGE.WEBSITE.SEARCH_PLACEHOLDER')"
          :custom-input-class="['ltr:!pl-8 rtl:!pr-8']"
          class="flex-1 min-w-48"
        >
          <template #prefix>
            <Icon
              icon="i-lucide-search"
              class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
            />
          </template>
        </Input>
        <Button
          v-if="selectedIds.length"
          :label="
            t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE_SELECTED', {
              count: selectedIds.length,
            })
          "
          icon="i-lucide-trash-2"
          color="ruby"
          variant="faded"
          @click="openDeleteDialog(selectedIds)"
        />
      </div>

      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner />
      </div>
      <p
        v-else-if="!filteredSources.length"
        class="px-6 py-10 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        {{
          searchQuery
            ? t('AI_AGENTS.KNOWLEDGE.WEBSITE.NO_RESULTS')
            : t('AI_AGENTS.KNOWLEDGE.WEBSITE.EMPTY')
        }}
      </p>
      <ul v-else class="flex flex-col divide-y divide-n-weak">
        <li
          v-for="source in filteredSources"
          :key="source.id"
          class="flex flex-wrap items-center gap-x-3 gap-y-2 py-3"
        >
          <Checkbox
            :model-value="selectedIds.includes(source.id)"
            @update:model-value="toggleSource(source.id, $event)"
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="truncate text-heading-3 text-n-slate-12">
              {{ source.title }}
            </span>
            <a
              :href="source.external_url"
              target="_blank"
              rel="noopener noreferrer"
              class="truncate text-body-main text-n-slate-11 hover:underline"
            >
              {{ source.external_url }}
            </a>
          </div>
          <SourceStatusBadge
            :status="source.status"
            :error-message="source.error_message"
          />
          <span
            v-if="source.status === 'ready'"
            class="tabular-nums text-body-main text-n-slate-11"
          >
            {{
              t('AI_AGENTS.KNOWLEDGE.CHARACTERS', {
                count: formatNumber(source.characters),
              })
            }}
          </span>
          <Button
            v-if="source.status === 'ready'"
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', { title: source.title })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', { title: source.title })
            "
            icon="i-lucide-layers"
            color="slate"
            variant="ghost"
            size="sm"
            @click="emit('viewChunks', source)"
          />
          <Button
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.WEBSITE.RESYNC', { title: source.title })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.WEBSITE.RESYNC', { title: source.title })
            "
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="ghost"
            size="sm"
            :disabled="['pending', 'processing'].includes(source.status)"
            @click="resync(source)"
          />
          <Button
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE', { title: source.title })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE', { title: source.title })
            "
            icon="i-lucide-trash-2"
            color="slate"
            variant="ghost"
            size="sm"
            @click="openDeleteDialog([source.id])"
          />
        </li>
      </ul>
    </div>

    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="
        t(
          'AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE_TITLE',
          { count: deletingIds.length },
          deletingIds.length
        )
      "
      :description="t('AI_AGENTS.KNOWLEDGE.WEBSITE.DELETE_DESCRIPTION')"
      :is-loading="isDeleting"
      @confirm="deleteSources"
    />
  </section>
</template>
