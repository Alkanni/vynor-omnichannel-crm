<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';
import PromotionFormDialog from '../../components/PromotionFormDialog.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged']);

const SEARCH_DEBOUNCE_MS = 300;
// The All tab sends no status.
const STATUS_FILTERS = ['', 'active', 'scheduled', 'archived'];
const STATUS_LABELS = {
  active: 'AI_AGENTS.KNOWLEDGE.PROMOTION.STATUS.ACTIVE',
  scheduled: 'AI_AGENTS.KNOWLEDGE.PROMOTION.STATUS.SCHEDULED',
  archived: 'AI_AGENTS.KNOWLEDGE.PROMOTION.STATUS.ARCHIVED',
};
const STATUS_STYLES = {
  active: 'bg-n-teal-3 text-n-teal-11',
  scheduled: 'bg-n-blue-3 text-n-blue-11',
  archived: 'bg-n-slate-3 text-n-slate-11',
};

const { t, locale } = useI18n();

const promotions = ref([]);
const searchQuery = ref('');
const statusFilter = ref('');
const selectedIds = ref([]);
const isLoading = ref(true);
const isDeleting = ref(false);
const deletingIds = ref([]);
const formDialogRef = ref(null);
const deleteDialogRef = ref(null);

const tabs = computed(() =>
  STATUS_FILTERS.map(status => ({
    value: status,
    label: status
      ? t(STATUS_LABELS[status])
      : t('AI_AGENTS.KNOWLEDGE.PROMOTION.FILTERS.ALL'),
  }))
);
const activeTab = computed(() => STATUS_FILTERS.indexOf(statusFilter.value));
const isFiltered = computed(() =>
  Boolean(searchQuery.value || statusFilter.value)
);
const allSelected = computed(
  () =>
    promotions.value.length > 0 &&
    selectedIds.value.length === promotions.value.length
);
const someSelected = computed(
  () => selectedIds.value.length > 0 && !allSelected.value
);
const deleteDialogTitle = computed(() => {
  if (deletingIds.value.length === 1) {
    const promotion = promotions.value.find(
      item => item.id === deletingIds.value[0]
    );
    return t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE_TITLE', {
      title: promotion?.title,
    });
  }
  return t('AI_AGENTS.KNOWLEDGE.PROMOTION.BULK_DELETE_TITLE', {
    count: deletingIds.value.length,
  });
});
const deleteDialogDescription = computed(() =>
  deletingIds.value.length === 1
    ? t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE_DESCRIPTION')
    : t('AI_AGENTS.KNOWLEDGE.PROMOTION.BULK_DELETE_DESCRIPTION')
);

// Promotion dates are calendar days (YYYY-MM-DD), so they are formatted in UTC to keep the same day in every timezone.
const formatDate = date =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeZone: 'UTC',
  }).format(new Date(`${date}T00:00:00Z`));

const periodText = ({ starts_on: from, ends_on: to }) => {
  if (from && to) {
    return t('AI_AGENTS.KNOWLEDGE.PROMOTION.PERIOD.RANGE', {
      from: formatDate(from),
      to: formatDate(to),
    });
  }
  if (from) {
    return t('AI_AGENTS.KNOWLEDGE.PROMOTION.PERIOD.FROM', {
      from: formatDate(from),
    });
  }
  if (to) {
    return t('AI_AGENTS.KNOWLEDGE.PROMOTION.PERIOD.UNTIL', {
      to: formatDate(to),
    });
  }
  return t('AI_AGENTS.KNOWLEDGE.PROMOTION.PERIOD.ALWAYS');
};

const fetchPromotions = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiAgentKnowledgeAPI.getPromotions(props.agent.id, {
      query: searchQuery.value.trim(),
      status: statusFilter.value,
    });
    promotions.value = data.payload;
    const ids = new Set(data.payload.map(promotion => promotion.id));
    selectedIds.value = selectedIds.value.filter(id => ids.has(id));
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};
const debouncedFetch = debounce(fetchPromotions, SEARCH_DEBOUNCE_MS);

const toggleAll = checked => {
  selectedIds.value = checked
    ? promotions.value.map(promotion => promotion.id)
    : [];
};

const togglePromotion = (promotionId, checked) => {
  selectedIds.value = checked
    ? [...selectedIds.value, promotionId]
    : selectedIds.value.filter(id => id !== promotionId);
};

const openDeleteDialog = ids => {
  deletingIds.value = ids;
  deleteDialogRef.value.open();
};

const deletePromotions = async () => {
  isDeleting.value = true;
  try {
    if (deletingIds.value.length === 1) {
      await AiAgentKnowledgeAPI.deletePromotion(
        props.agent.id,
        deletingIds.value[0]
      );
    } else {
      await AiAgentKnowledgeAPI.bulkDeletePromotions(
        props.agent.id,
        deletingIds.value
      );
    }
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE_SUCCESS'));
    await fetchPromotions();
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

const onPromotionSaved = async () => {
  await fetchPromotions();
  emit('knowledgeChanged');
};

watch(searchQuery, debouncedFetch);
watch(statusFilter, fetchPromotions);
watch(() => props.agent.id, fetchPromotions, { immediate: true });
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <h2 class="text-heading-2 text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.TITLE') }}
      </h2>
      <p class="max-w-3xl text-body-para text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.DESCRIPTION') }}
      </p>
    </header>

    <div class="min-w-0 p-1 -m-1 overflow-x-auto no-scrollbar">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTab"
        @tab-changed="tab => (statusFilter = tab.value)"
      />
    </div>

    <div class="flex flex-wrap items-center gap-3">
      <label class="flex items-center gap-2 cursor-pointer shrink-0">
        <Checkbox
          :model-value="allSelected"
          :indeterminate="someSelected"
          :disabled="!promotions.length"
          @update:model-value="toggleAll"
        />
        <span class="text-body-main text-n-blue-11">
          {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.SELECT') }}
        </span>
      </label>
      <Input
        v-model="searchQuery"
        type="search"
        :placeholder="t('AI_AGENTS.KNOWLEDGE.PROMOTION.SEARCH_PLACEHOLDER')"
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
          t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE_SELECTED', {
            count: selectedIds.length,
          })
        "
        icon="i-lucide-trash-2"
        color="ruby"
        variant="faded"
        @click="openDeleteDialog(selectedIds)"
      />
      <Button
        :label="t('AI_AGENTS.KNOWLEDGE.PROMOTION.ADD')"
        icon="i-lucide-badge-percent"
        @click="formDialogRef.open()"
      />
    </div>

    <div
      v-if="isLoading && !promotions.length"
      class="flex justify-center py-10"
    >
      <Spinner />
    </div>
    <p
      v-else-if="!promotions.length"
      class="px-6 py-12 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      {{
        isFiltered
          ? t('AI_AGENTS.KNOWLEDGE.PROMOTION.NO_RESULTS')
          : t('AI_AGENTS.KNOWLEDGE.PROMOTION.EMPTY')
      }}
    </p>
    <ul v-else class="flex flex-col divide-y divide-n-weak">
      <li
        v-for="promotion in promotions"
        :key="promotion.id"
        class="flex flex-wrap items-center gap-x-4 gap-y-2 py-4"
      >
        <Checkbox
          :model-value="selectedIds.includes(promotion.id)"
          @update:model-value="togglePromotion(promotion.id, $event)"
        />
        <button
          type="button"
          class="flex flex-col flex-1 min-w-56 gap-0.5 text-start"
          :aria-label="
            t('AI_AGENTS.KNOWLEDGE.PROMOTION.EDIT', { title: promotion.title })
          "
          @click="formDialogRef.open(promotion)"
        >
          <span class="flex items-center gap-2 min-w-0">
            <span class="truncate text-heading-3 text-n-slate-12">
              {{ promotion.title }}
            </span>
            <span
              class="px-2 py-0.5 rounded-md shrink-0 text-label-small"
              :class="STATUS_STYLES[promotion.status]"
            >
              {{ t(STATUS_LABELS[promotion.status]) }}
            </span>
          </span>
          <span class="truncate text-body-main text-n-slate-11">
            {{ promotion.description }}
          </span>
          <span
            v-if="promotion.products.length"
            class="truncate text-label-small text-n-slate-10"
          >
            {{
              t('AI_AGENTS.KNOWLEDGE.PROMOTION.APPLIES_TO', {
                products: promotion.products
                  .map(product => product.name)
                  .join(', '),
              })
            }}
          </span>
        </button>
        <span class="text-body-main tabular-nums text-n-slate-11 sm:w-56">
          {{ periodText(promotion) }}
        </span>
        <Button
          v-tooltip.top="
            t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE', {
              title: promotion.title,
            })
          "
          :aria-label="
            t('AI_AGENTS.KNOWLEDGE.PROMOTION.DELETE', {
              title: promotion.title,
            })
          "
          icon="i-lucide-trash-2"
          color="slate"
          variant="ghost"
          size="sm"
          @click="openDeleteDialog([promotion.id])"
        />
      </li>
    </ul>

    <PromotionFormDialog
      ref="formDialogRef"
      :agent-id="agent.id"
      :timezone="agent.timezone"
      @saved="onPromotionSaved"
    />
    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="deleteDialogTitle"
      :description="deleteDialogDescription"
      :is-loading="isDeleting"
      @confirm="deletePromotions"
    />
  </section>
</template>
