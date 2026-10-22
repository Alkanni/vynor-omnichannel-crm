<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';
import SourceStatusBadge from '../../components/SourceStatusBadge.vue';
import { useProcessingPoll } from '../../composables/useProcessingPoll';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged']);

const SOURCE_TYPE = 'file';
const MAX_FILE_SIZE = 100 * 1024 * 1024;
const ALLOWED_EXTENSIONS = ['.pdf', '.doc', '.docx', '.txt', '.md'];

const { t, locale } = useI18n();

const sources = ref([]);
const queue = ref([]);
const isLoading = ref(true);
const isDragging = ref(false);
const isUploading = ref(false);
const uploadStatus = ref('');
const fileInputRef = ref(null);
const deleteDialogRef = ref(null);
const deletingSource = ref(null);
const isDeleting = ref(false);

const formatNumber = value => new Intl.NumberFormat(locale.value).format(value);
const extensionOf = name => name.slice(name.lastIndexOf('.')).toLowerCase();

const fetchSources = async () => {
  try {
    const { data } = await AiAgentKnowledgeAPI.getSources(
      props.agent.id,
      SOURCE_TYPE
    );
    sources.value = data.payload;
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const { hasInProgress } = useProcessingPoll(sources, fetchSources);

const addToQueue = files => {
  Array.from(files).forEach(file => {
    if (!ALLOWED_EXTENSIONS.includes(extensionOf(file.name))) {
      useAlert(t('AI_AGENTS.KNOWLEDGE.FILE.UNSUPPORTED', { name: file.name }));
    } else if (file.size > MAX_FILE_SIZE) {
      useAlert(t('AI_AGENTS.KNOWLEDGE.FILE.TOO_LARGE', { name: file.name }));
    } else {
      queue.value = [...queue.value, file];
    }
  });
};

const onFileInput = event => {
  addToQueue(event.target.files);
  event.target.value = '';
};

const onDrop = event => {
  isDragging.value = false;
  addToQueue(event.dataTransfer.files);
};

const removeFromQueue = index => {
  queue.value = queue.value.filter((_, position) => position !== index);
};

const uploadQueue = async () => {
  isUploading.value = true;
  let uploaded = 0;
  // Files are uploaded one at a time to keep large uploads within memory and bandwidth limits.
  // eslint-disable-next-line no-restricted-syntax
  for (const file of [...queue.value]) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await AiAgentKnowledgeAPI.uploadFile(props.agent.id, file, event => {
        const progress = Math.round((event.loaded / event.total) * 100);
        uploadStatus.value = t('AI_AGENTS.KNOWLEDGE.FILE.UPLOADING', {
          name: file.name,
          progress,
        });
      });
      queue.value = queue.value.filter(item => item !== file);
      uploaded += 1;
    } catch (error) {
      const reason = parseAPIErrorResponse(error);
      useAlert(
        t('AI_AGENTS.KNOWLEDGE.FILE.UPLOAD_ERROR', {
          name: file.name,
          reason: typeof reason === 'string' ? reason : '',
        })
      );
    }
  }
  uploadStatus.value = '';
  isUploading.value = false;
  if (uploaded > 0) {
    useAlert(t('AI_AGENTS.KNOWLEDGE.FILE.UPLOAD_SUCCESS'));
    await fetchSources();
    emit('knowledgeChanged');
  }
};

const retry = async source => {
  try {
    await AiAgentKnowledgeAPI.resyncSource(props.agent.id, source.id);
    await fetchSources();
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.WEBSITE.RESYNC_ERROR'));
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
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.FILE.DELETE_SUCCESS'));
    await fetchSources();
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.FILE.DELETE_ERROR'));
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
  <section class="flex flex-col gap-5">
    <h2 class="text-heading-2 text-n-slate-12">
      {{ t('AI_AGENTS.KNOWLEDGE.FILE.TITLE') }}
    </h2>

    <div class="flex flex-col gap-2">
      <button
        type="button"
        class="flex flex-col items-center justify-center gap-2 px-6 border-2 border-dashed rounded-xl min-h-44 text-center transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          isDragging
            ? 'border-n-brand bg-n-alpha-2'
            : 'border-n-weak hover:bg-n-alpha-1'
        "
        @click="fileInputRef.click()"
        @dragover.prevent="isDragging = true"
        @dragleave.prevent="isDragging = false"
        @drop.prevent="onDrop"
      >
        <Icon icon="i-lucide-upload" class="size-6 text-n-slate-10" />
        <span class="text-heading-3 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.FILE.DROPZONE') }}
        </span>
        <span class="text-body-main text-n-slate-11">
          {{ t('AI_AGENTS.KNOWLEDGE.FILE.SUPPORTED') }}
        </span>
      </button>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        :accept="ALLOWED_EXTENSIONS.join(',')"
        class="hidden"
        @change="onFileInput"
      />
      <p class="text-center text-label-small text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.FILE.PDF_NOTE') }}
      </p>
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.FILE.INCLUDED_TITLE') }}
      </h3>
      <div v-if="isLoading" class="flex justify-center py-6">
        <Spinner />
      </div>
      <p v-else-if="!sources.length" class="text-body-main text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.FILE.INCLUDED_EMPTY') }}
      </p>
      <ul v-else class="flex flex-col divide-y divide-n-weak">
        <li
          v-for="source in sources"
          :key="source.id"
          class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2"
        >
          <Icon icon="i-lucide-file-text" class="size-4 text-n-slate-10" />
          <span class="flex-1 min-w-0 truncate text-body-main text-n-slate-12">
            {{ source.title }}
          </span>
          <span
            v-if="source.status === 'ready'"
            class="tabular-nums text-heading-3 text-n-slate-12"
          >
            {{
              t('AI_AGENTS.KNOWLEDGE.CHARACTERS', {
                count: formatNumber(source.characters),
              })
            }}
          </span>
          <SourceStatusBadge
            :status="source.status"
            :error-message="source.error_message"
          />
          <Button
            v-if="source.status === 'failed'"
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.FILE.RETRY', { title: source.title })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.FILE.RETRY', { title: source.title })
            "
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="ghost"
            size="xs"
            @click="retry(source)"
          />
          <Button
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.FILE.DELETE', { title: source.title })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.FILE.DELETE', { title: source.title })
            "
            icon="i-lucide-trash-2"
            color="ruby"
            variant="ghost"
            size="xs"
            @click="openDeleteDialog(source)"
          />
        </li>
      </ul>
    </div>

    <div class="flex flex-col gap-2">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.FILE.QUEUE_TITLE') }}
          <span v-if="!queue.length" class="text-n-slate-11">
            {{ t('AI_AGENTS.KNOWLEDGE.FILE.QUEUE_EMPTY') }}
          </span>
        </h3>
        <Button
          :label="t('AI_AGENTS.KNOWLEDGE.FILE.SAVE')"
          :disabled="!queue.length || isUploading"
          :is-loading="isUploading"
          @click="uploadQueue"
        />
      </div>
      <p v-if="uploadStatus" class="text-body-main text-n-slate-11">
        {{ uploadStatus }}
      </p>
      <ul v-if="queue.length" class="flex flex-col gap-1">
        <li
          v-for="(file, index) in queue"
          :key="`${file.name}-${file.size}-${file.lastModified}`"
          class="flex items-center gap-2"
        >
          <Icon icon="i-lucide-file-plus" class="size-4 text-n-brand" />
          <span class="flex-1 min-w-0 truncate text-body-main text-n-slate-12">
            {{ file.name }}
          </span>
          <Button
            v-tooltip.top="
              t('AI_AGENTS.KNOWLEDGE.FILE.REMOVE_FROM_QUEUE', {
                name: file.name,
              })
            "
            :aria-label="
              t('AI_AGENTS.KNOWLEDGE.FILE.REMOVE_FROM_QUEUE', {
                name: file.name,
              })
            "
            icon="i-lucide-x"
            color="slate"
            variant="ghost"
            size="xs"
            :disabled="isUploading"
            @click="removeFromQueue(index)"
          />
        </li>
      </ul>
    </div>

    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="
        t('AI_AGENTS.KNOWLEDGE.FILE.DELETE_TITLE', {
          title: deletingSource?.title,
        })
      "
      :description="t('AI_AGENTS.KNOWLEDGE.FILE.DELETE_DESCRIPTION')"
      :is-loading="isDeleting"
      @confirm="deleteSource"
    />
  </section>
</template>
