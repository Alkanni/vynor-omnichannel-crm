<script setup>
import { computed, onBeforeUnmount, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
  // ISO 4217 code of the prices, blank until the product list has loaded.
  currency: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['saved']);

const MAX_IMAGE_SIZE = 5 * 1024 * 1024;
const IMAGE_TYPES = 'image/jpeg,image/png,image/gif,image/webp';

const { t } = useI18n();

const dialogRef = ref(null);
const fileInputRef = ref(null);
const productId = ref(null);
const imageFile = ref(null);
const imagePreview = ref('');
const isSaving = ref(false);
// Price, weight, and stock stay blank when they are not recorded; the API stores a blank one as null.
const form = reactive({
  name: '',
  description: '',
  price: '',
  weight: '',
  stock: '',
});

const isEditing = computed(() => Boolean(productId.value));
const priceLabel = computed(() =>
  props.currency
    ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.PRICE_IN_CURRENCY', {
        currency: props.currency,
      })
    : t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.PRICE')
);
const canSubmit = computed(() => Boolean(form.name.trim()));

const revokePreview = () => {
  if (imagePreview.value.startsWith('blob:')) {
    URL.revokeObjectURL(imagePreview.value);
  }
};

const open = (product = null) => {
  revokePreview();
  productId.value = product?.id || null;
  Object.assign(form, {
    name: product?.name || '',
    description: product?.description || '',
    price: product?.price ?? '',
    weight: product?.weight ?? '',
    stock: product?.stock ?? '',
  });
  imageFile.value = null;
  imagePreview.value = product?.image_url || '';
  dialogRef.value.open();
};

const onImageSelected = event => {
  const [file] = event.target.files;
  event.target.value = '';
  if (!file) return;
  if (file.size > MAX_IMAGE_SIZE) {
    useAlert(t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.IMAGE_TOO_LARGE'));
    return;
  }

  revokePreview();
  imageFile.value = file;
  imagePreview.value = URL.createObjectURL(file);
};

const buildFormData = () => {
  const formData = new FormData();
  formData.append('name', form.name.trim());
  formData.append('description', form.description);
  formData.append('price', form.price);
  formData.append('weight', form.weight);
  formData.append('stock', form.stock);
  if (imageFile.value) formData.append('image', imageFile.value);
  return formData;
};

const submit = async () => {
  if (!canSubmit.value) return;

  isSaving.value = true;
  try {
    const formData = buildFormData();
    if (isEditing.value) {
      await AiAgentKnowledgeAPI.updateProduct(
        props.agentId,
        productId.value,
        formData
      );
    } else {
      await AiAgentKnowledgeAPI.createProduct(props.agentId, formData);
    }
    useAlert(t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.SAVE_SUCCESS'));
    dialogRef.value.close();
    emit('saved');
  } catch (error) {
    const message = parseAPIErrorResponse(error);
    useAlert(
      typeof message === 'string'
        ? message
        : t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onBeforeUnmount(revokePreview);

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="
      isEditing
        ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.EDIT_TITLE')
        : t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.CREATE_TITLE')
    "
    :confirm-button-label="
      isEditing
        ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.EDIT_CONFIRM')
        : t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.CREATE_CONFIRM')
    "
    :disable-confirm-button="!canSubmit"
    :is-loading="isSaving"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <div class="flex items-center gap-4">
        <div
          class="flex items-center justify-center overflow-hidden rounded-lg size-16 shrink-0 bg-n-alpha-2 text-n-slate-10"
        >
          <img
            v-if="imagePreview"
            :src="imagePreview"
            alt=""
            class="object-cover size-full"
          />
          <Icon v-else icon="i-lucide-image" class="size-6" />
        </div>
        <div class="flex flex-col items-start gap-1">
          <Button
            type="button"
            :label="
              imagePreview
                ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.CHANGE_IMAGE')
                : t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.UPLOAD_IMAGE')
            "
            icon="i-lucide-upload"
            color="slate"
            variant="faded"
            size="sm"
            @click="fileInputRef.click()"
          />
          <span class="text-label-small text-n-slate-11">
            {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.IMAGE_HINT') }}
          </span>
          <input
            ref="fileInputRef"
            type="file"
            :accept="IMAGE_TYPES"
            class="hidden"
            @change="onImageSelected"
          />
        </div>
      </div>
      <Input
        id="ai-agent-product-name"
        v-model="form.name"
        :label="t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.NAME')"
        :placeholder="t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.NAME_PLACEHOLDER')"
      />
      <TextArea
        id="ai-agent-product-description"
        v-model="form.description"
        :label="t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.DESCRIPTION')"
        :placeholder="
          t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.DESCRIPTION_PLACEHOLDER')
        "
        :max-length="5000"
        show-character-count
        auto-height
        min-height="5rem"
      />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Input
          id="ai-agent-product-price"
          v-model="form.price"
          type="number"
          min="0"
          :label="priceLabel"
        />
        <Input
          id="ai-agent-product-weight"
          v-model="form.weight"
          type="number"
          min="0"
          :label="t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.WEIGHT')"
        />
        <Input
          id="ai-agent-product-stock"
          v-model="form.stock"
          type="number"
          min="0"
          :label="t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.STOCK')"
        />
      </div>
      <p class="-mt-2 text-label-small text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.FORM.OPTIONAL_NUMBERS_HINT') }}
      </p>
    </div>
  </Dialog>
</template>
