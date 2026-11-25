<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
  // The AI agent's timezone, which the promotion dates follow.
  timezone: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['saved']);

const MAX_DESCRIPTION_LENGTH = 5000;

const { t } = useI18n();

const dialogRef = ref(null);
const promotionId = ref(null);
const productOptions = ref([]);
const isSaving = ref(false);
// A promotion needs an end date unless No end date is checked, so it never runs forever by accident.
const noEndDate = ref(false);
const form = reactive({
  title: '',
  description: '',
  starts_on: '',
  ends_on: '',
  product_ids: [],
});

const isEditing = computed(() => Boolean(promotionId.value));
const canSubmit = computed(
  () =>
    Boolean(form.title.trim() && form.description.trim()) &&
    (noEndDate.value || Boolean(form.ends_on))
);

const fetchProducts = async () => {
  try {
    const { data } = await AiAgentKnowledgeAPI.getProducts(props.agentId);
    productOptions.value = data.payload.map(product => ({
      value: product.id,
      label: product.name,
    }));
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  }
};

const open = (promotion = null) => {
  promotionId.value = promotion?.id || null;
  Object.assign(form, {
    title: promotion?.title || '',
    description: promotion?.description || '',
    starts_on: promotion?.starts_on || '',
    ends_on: promotion?.ends_on || '',
    product_ids: promotion ? promotion.products.map(product => product.id) : [],
  });
  noEndDate.value = Boolean(promotion) && !promotion.ends_on;
  fetchProducts();
  dialogRef.value.open();
};

const setNoEndDate = checked => {
  noEndDate.value = checked;
  if (checked) form.ends_on = '';
};

const submit = async () => {
  if (!canSubmit.value) return;

  isSaving.value = true;
  const data = { ...form, title: form.title.trim() };
  try {
    if (isEditing.value) {
      await AiAgentKnowledgeAPI.updatePromotion(
        props.agentId,
        promotionId.value,
        data
      );
    } else {
      await AiAgentKnowledgeAPI.createPromotion(props.agentId, data);
    }
    useAlert(t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.SAVE_SUCCESS'));
    dialogRef.value.close();
    emit('saved');
  } catch (error) {
    const message = parseAPIErrorResponse(error);
    useAlert(
      typeof message === 'string'
        ? message
        : t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="
      isEditing
        ? t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.EDIT_TITLE')
        : t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.CREATE_TITLE')
    "
    :confirm-button-label="
      isEditing
        ? t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.EDIT_CONFIRM')
        : t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.CREATE_CONFIRM')
    "
    :disable-confirm-button="!canSubmit"
    :is-loading="isSaving"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <Input
        id="ai-agent-promotion-title"
        v-model="form.title"
        :label="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.TITLE')"
        :placeholder="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.TITLE_PLACEHOLDER')"
      />
      <TextArea
        id="ai-agent-promotion-description"
        v-model="form.description"
        :label="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.DESCRIPTION')"
        :placeholder="
          t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.DESCRIPTION_PLACEHOLDER')
        "
        :max-length="MAX_DESCRIPTION_LENGTH"
        show-character-count
        auto-height
        min-height="5rem"
      />
      <p class="-mt-2 text-label-small text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.DESCRIPTION_HINT') }}
      </p>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          id="ai-agent-promotion-starts-on"
          v-model="form.starts_on"
          type="date"
          :label="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.STARTS_ON')"
        />
        <div class="flex flex-col gap-2">
          <Input
            id="ai-agent-promotion-ends-on"
            v-model="form.ends_on"
            type="date"
            :min="form.starts_on"
            :disabled="noEndDate"
            :label="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.ENDS_ON')"
          />
          <label class="flex items-center gap-2 cursor-pointer">
            <Checkbox
              :model-value="noEndDate"
              @update:model-value="setNoEndDate"
            />
            <span class="text-body-main text-n-slate-12">
              {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.NO_END_DATE') }}
            </span>
          </label>
        </div>
      </div>
      <p class="-mt-2 text-label-small text-n-slate-11">
        {{
          t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PERIOD_HINT', {
            timezone,
          })
        }}
      </p>
      <div class="flex flex-col gap-1">
        <span class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PRODUCTS') }}
        </span>
        <TagMultiSelectComboBox
          v-model="form.product_ids"
          :options="productOptions"
          :placeholder="
            t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PRODUCTS_PLACEHOLDER')
          "
          :search-placeholder="
            t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PRODUCTS_SEARCH_PLACEHOLDER')
          "
          :empty-state="t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PRODUCTS_EMPTY')"
        />
        <p class="mt-1 text-label-small text-n-slate-11">
          {{ t('AI_AGENTS.KNOWLEDGE.PROMOTION.FORM.PRODUCTS_HINT') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
