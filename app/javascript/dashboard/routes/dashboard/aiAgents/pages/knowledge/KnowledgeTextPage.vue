<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';
import SourceIndexStatus from '../../components/SourceIndexStatus.vue';
import TextSourceTitleDialog from '../../components/TextSourceTitleDialog.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged', 'viewChunks']);

const SOURCE_TYPE = 'text';
const MAX_CONTENT_LENGTH = 100000;

const { t } = useI18n();

const sources = ref([]);
const drafts = reactive({});
const activeId = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);
const isSubmittingTitle = ref(false);
const isDeleting = ref(false);
const titleDialogRef = ref(null);
const deleteDialogRef = ref(null);
const renamingSource = ref(null);
const deletingSource = ref(null);

const activeSource = computed(() =>
  sources.value.find(source => source.id === activeId.value)
);
const dirtySources = computed(() =>
  sources.value.filter(source => drafts[source.id] !== (source.content || ''))
);

const activeDraft = computed({
  get: () => drafts[activeId.value] ?? '',
  set: value => {
    drafts[activeId.value] = value;
  },
});

const fetchSources = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiAgentKnowledgeAPI.getSources(
      props.agent.id,
      SOURCE_TYPE
    );
    sources.value = data.payload;
    Object.keys(drafts).forEach(id => delete drafts[id]);
    data.payload.forEach(source => {
      drafts[source.id] = source.content || '';
    });
    activeId.value = data.payload[0]?.id ?? null;
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const replaceSource = updated => {
  sources.value = sources.value.map(source =>
    source.id === updated.id ? updated : source
  );
};

const saveAll = async () => {
  isSaving.value = true;
  const results = await Promise.allSettled(
    dirtySources.value.map(source =>
      AiAgentKnowledgeAPI.updateSource(props.agent.id, source.id, {
        content: drafts[source.id],
      })
    )
  );
  results
    .filter(result => result.status === 'fulfilled')
    .forEach(result => replaceSource(result.value.data));
  const hasFailure = results.some(result => result.status === 'rejected');
  useAlert(
    hasFailure
      ? t('AI_AGENTS.KNOWLEDGE.TEXT.SAVE_ERROR')
      : t('AI_AGENTS.KNOWLEDGE.TEXT.SAVE_SUCCESS')
  );
  isSaving.value = false;
  emit('knowledgeChanged');
};

const openCreateDialog = () => {
  renamingSource.value = null;
  titleDialogRef.value.open();
};

const openRenameDialog = source => {
  renamingSource.value = source;
  titleDialogRef.value.open(source.title);
};

const submitTitle = async title => {
  isSubmittingTitle.value = true;
  try {
    if (renamingSource.value) {
      const { data } = await AiAgentKnowledgeAPI.updateSource(
        props.agent.id,
        renamingSource.value.id,
        { title }
      );
      replaceSource(data);
    } else {
      const { data } = await AiAgentKnowledgeAPI.createSource(props.agent.id, {
        source_type: SOURCE_TYPE,
        title,
        content: '',
      });
      sources.value = [...sources.value, data];
      drafts[data.id] = '';
      activeId.value = data.id;
    }
    titleDialogRef.value.close();
  } catch {
    useAlert(
      renamingSource.value
        ? t('AI_AGENTS.KNOWLEDGE.TEXT.RENAME_ERROR')
        : t('AI_AGENTS.KNOWLEDGE.TEXT.CREATE_ERROR')
    );
  } finally {
    isSubmittingTitle.value = false;
  }
};

const openDeleteDialog = source => {
  deletingSource.value = source;
  deleteDialogRef.value.open();
};

const deleteSource = async () => {
  isDeleting.value = true;
  try {
    await AiAgentKnowledgeAPI.deleteSource(
      props.agent.id,
      deletingSource.value.id
    );
    sources.value = sources.value.filter(
      source => source.id !== deletingSource.value.id
    );
    delete drafts[deletingSource.value.id];
    if (activeId.value === deletingSource.value.id) {
      activeId.value = sources.value[0]?.id ?? null;
    }
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE_SUCCESS'));
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

watch(() => props.agent.id, fetchSources, { immediate: true });
</script>

<template>
  <section class="flex flex-col gap-4">
    <div v-if="isLoading" class="flex justify-center py-10">
      <Spinner />
    </div>

    <div
      v-else-if="!sources.length"
      class="flex flex-col items-center gap-3 px-6 py-12 text-center rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <h2 class="text-heading-2 text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.TEXT.EMPTY_TITLE') }}
      </h2>
      <p class="max-w-md text-body-para text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.TEXT.EMPTY_DESCRIPTION') }}
      </p>
      <Button
        :label="t('AI_AGENTS.KNOWLEDGE.TEXT.ADD')"
        icon="i-lucide-plus"
        @click="openCreateDialog"
      />
    </div>

    <template v-else>
      <div class="flex items-center gap-3">
        <div class="flex items-center flex-1 min-w-0 gap-2 overflow-x-auto">
          <Button
            v-tooltip.top="t('AI_AGENTS.KNOWLEDGE.TEXT.ADD')"
            :aria-label="t('AI_AGENTS.KNOWLEDGE.TEXT.ADD')"
            icon="i-lucide-plus"
            color="slate"
            variant="ghost"
            size="sm"
            class="shrink-0"
            @click="openCreateDialog"
          />
          <div
            v-for="source in sources"
            :key="source.id"
            class="flex items-center gap-1 py-1 rounded-lg shrink-0 ps-3 pe-1 outline outline-1 -outline-offset-1"
            :class="
              source.id === activeId
                ? 'bg-n-alpha-2 outline-n-brand'
                : 'outline-n-weak hover:bg-n-alpha-1'
            "
          >
            <button
              type="button"
              class="truncate max-w-40 text-body-main"
              :class="
                source.id === activeId ? 'text-n-blue-11' : 'text-n-slate-11'
              "
              @click="activeId = source.id"
            >
              {{ source.title }}
            </button>
            <span
              v-if="drafts[source.id] !== (source.content || '')"
              v-tooltip.top="t('AI_AGENTS.KNOWLEDGE.TEXT.UNSAVED')"
              :aria-label="t('AI_AGENTS.KNOWLEDGE.TEXT.UNSAVED')"
              role="img"
              class="rounded-full size-1.5 shrink-0 bg-n-amber-9"
            />
            <SourceIndexStatus :index="source.index" />
            <Button
              v-tooltip.top="
                t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', { title: source.title })
              "
              :aria-label="
                t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', { title: source.title })
              "
              icon="i-lucide-layers"
              color="slate"
              variant="ghost"
              size="xs"
              @click="emit('viewChunks', source)"
            />
            <Button
              v-tooltip.top="
                t('AI_AGENTS.KNOWLEDGE.TEXT.RENAME', { title: source.title })
              "
              :aria-label="
                t('AI_AGENTS.KNOWLEDGE.TEXT.RENAME', { title: source.title })
              "
              icon="i-lucide-pencil"
              color="slate"
              variant="ghost"
              size="xs"
              @click="openRenameDialog(source)"
            />
            <Button
              v-tooltip.top="
                t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE', { title: source.title })
              "
              :aria-label="
                t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE', { title: source.title })
              "
              icon="i-lucide-x"
              color="slate"
              variant="ghost"
              size="xs"
              @click="openDeleteDialog(source)"
            />
          </div>
        </div>
        <Button
          :label="t('AI_AGENTS.KNOWLEDGE.TEXT.SAVE')"
          :disabled="!dirtySources.length || isSaving"
          :is-loading="isSaving"
          class="shrink-0"
          @click="saveAll"
        />
      </div>

      <TextArea
        v-if="activeSource"
        :id="`ai-agent-text-${activeSource.id}`"
        :key="activeSource.id"
        v-model="activeDraft"
        :placeholder="t('AI_AGENTS.KNOWLEDGE.TEXT.PLACEHOLDER')"
        :max-length="MAX_CONTENT_LENGTH"
        show-character-count
        auto-height
        resize
        min-height="24rem"
        max-height="60vh"
      />
    </template>

    <TextSourceTitleDialog
      ref="titleDialogRef"
      :is-loading="isSubmittingTitle"
      @submit="submitTitle"
    />
    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="
        t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE_TITLE', {
          title: deletingSource?.title,
        })
      "
      :description="t('AI_AGENTS.KNOWLEDGE.TEXT.DELETE_DESCRIPTION')"
      :is-loading="isDeleting"
      @confirm="deleteSource"
    />
  </section>
</template>
