<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged', 'viewChunks']);

const SOURCE_TYPE = 'qa';
const MAX_QUESTION_LENGTH = 1000;
const MAX_ANSWER_LENGTH = 5000;

const { t } = useI18n();

const items = ref([]);
const isLoading = ref(true);
const isSaving = ref(false);
const isDeleting = ref(false);
const deleteDialogRef = ref(null);
const deletingItem = ref(null);
let newItemCount = 0;

const toItem = source => ({
  key: `qa-${source.id}`,
  id: source.id,
  question: source.title,
  answer: source.content,
  savedQuestion: source.title,
  savedAnswer: source.content,
});

const isChanged = item =>
  !item.id ||
  item.question !== item.savedQuestion ||
  item.answer !== item.savedAnswer;
const isComplete = item =>
  Boolean(item.question.trim()) && Boolean(item.answer.trim());

const changedItems = computed(() => items.value.filter(isChanged));
const hasIncompleteChanges = computed(() =>
  changedItems.value.some(item => !isComplete(item))
);
const canSave = computed(
  () =>
    changedItems.value.length > 0 &&
    !hasIncompleteChanges.value &&
    !isSaving.value
);

const fetchItems = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiAgentKnowledgeAPI.getSources(
      props.agent.id,
      SOURCE_TYPE
    );
    items.value = data.payload.map(toItem);
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const addItem = () => {
  newItemCount += 1;
  items.value = [
    {
      key: `new-${newItemCount}`,
      id: null,
      question: '',
      answer: '',
      savedQuestion: '',
      savedAnswer: '',
    },
    ...items.value,
  ];
};

const saveItem = item => {
  const payload = { title: item.question.trim(), content: item.answer.trim() };
  if (item.id) {
    return AiAgentKnowledgeAPI.updateSource(props.agent.id, item.id, payload);
  }
  return AiAgentKnowledgeAPI.createSource(props.agent.id, {
    ...payload,
    source_type: SOURCE_TYPE,
  });
};

const saveAll = async () => {
  isSaving.value = true;
  const pending = changedItems.value;
  const results = await Promise.allSettled(pending.map(saveItem));
  const savedByKey = {};
  results.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      savedByKey[pending[index].key] = toItem(result.value.data);
    }
  });
  items.value = items.value.map(item => savedByKey[item.key] || item);
  const hasFailure = results.some(result => result.status === 'rejected');
  useAlert(
    hasFailure
      ? t('AI_AGENTS.KNOWLEDGE.QA.SAVE_ERROR')
      : t('AI_AGENTS.KNOWLEDGE.QA.SAVE_SUCCESS')
  );
  isSaving.value = false;
  emit('knowledgeChanged');
};

const removeItem = item => {
  items.value = items.value.filter(current => current.key !== item.key);
};

const requestDelete = item => {
  if (!item.id) {
    removeItem(item);
    return;
  }
  deletingItem.value = item;
  deleteDialogRef.value.open();
};

const deleteItem = async () => {
  isDeleting.value = true;
  try {
    await AiAgentKnowledgeAPI.deleteSource(
      props.agent.id,
      deletingItem.value.id
    );
    removeItem(deletingItem.value);
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.QA.DELETE_SUCCESS'));
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.QA.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

watch(() => props.agent.id, fetchItems, { immediate: true });
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col gap-1 min-w-0">
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.QA.TITLE') }}
        </h2>
        <p class="max-w-xl text-body-para text-n-slate-11">
          {{ t('AI_AGENTS.KNOWLEDGE.QA.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          :label="t('AI_AGENTS.KNOWLEDGE.QA.ADD')"
          icon="i-lucide-plus"
          color="slate"
          variant="faded"
          @click="addItem"
        />
        <Button
          :label="t('AI_AGENTS.KNOWLEDGE.QA.SAVE')"
          :disabled="!canSave"
          :is-loading="isSaving"
          @click="saveAll"
        />
      </div>
    </header>

    <p v-if="hasIncompleteChanges" class="text-label-small text-n-amber-11">
      {{ t('AI_AGENTS.KNOWLEDGE.QA.INCOMPLETE') }}
    </p>

    <div v-if="isLoading" class="flex justify-center py-10">
      <Spinner />
    </div>
    <p
      v-else-if="!items.length"
      class="px-6 py-12 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      {{ t('AI_AGENTS.KNOWLEDGE.QA.EMPTY') }}
    </p>

    <template v-else>
      <article
        v-for="item in items"
        :key="item.key"
        class="flex flex-col gap-3 p-5 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1"
        :class="isChanged(item) ? 'outline-n-brand' : 'outline-n-container'"
      >
        <TextArea
          :id="`ai-agent-${item.key}-question`"
          v-model="item.question"
          :label="t('AI_AGENTS.KNOWLEDGE.QA.QUESTION')"
          :placeholder="t('AI_AGENTS.KNOWLEDGE.QA.QUESTION_PLACEHOLDER')"
          :max-length="MAX_QUESTION_LENGTH"
          show-character-count
          auto-height
          resize
          min-height="3rem"
        />
        <TextArea
          :id="`ai-agent-${item.key}-answer`"
          v-model="item.answer"
          :label="t('AI_AGENTS.KNOWLEDGE.QA.ANSWER')"
          :placeholder="t('AI_AGENTS.KNOWLEDGE.QA.ANSWER_PLACEHOLDER')"
          :max-length="MAX_ANSWER_LENGTH"
          show-character-count
          auto-height
          resize
          min-height="4rem"
        />
        <div class="flex justify-end gap-1">
          <Button
            v-if="item.id"
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', {
                title: item.savedQuestion,
              })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.CHUNKS.VIEW', {
                title: item.savedQuestion,
              })
            "
            icon="i-lucide-layers"
            color="slate"
            variant="ghost"
            size="sm"
            @click="
              emit('viewChunks', { id: item.id, title: item.savedQuestion })
            "
          />
          <Button
            v-tooltip.top="t('AI_AGENTS.KNOWLEDGE.QA.DELETE')"
            :aria-label="t('AI_AGENTS.KNOWLEDGE.QA.DELETE')"
            icon="i-lucide-trash-2"
            color="ruby"
            variant="ghost"
            size="sm"
            @click="requestDelete(item)"
          />
        </div>
      </article>
    </template>

    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="t('AI_AGENTS.KNOWLEDGE.QA.DELETE_TITLE')"
      :description="t('AI_AGENTS.KNOWLEDGE.QA.DELETE_DESCRIPTION')"
      :is-loading="isDeleting"
      @confirm="deleteItem"
    />
  </section>
</template>
