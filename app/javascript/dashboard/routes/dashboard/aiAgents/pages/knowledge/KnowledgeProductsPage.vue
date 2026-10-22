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
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog.vue';
import ProductFormDialog from '../../components/ProductFormDialog.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['knowledgeChanged']);

const SEARCH_DEBOUNCE_MS = 300;

const { t, locale } = useI18n();

const products = ref([]);
const searchQuery = ref('');
const selectedIds = ref([]);
const isLoading = ref(true);
const isDeleting = ref(false);
const deletingIds = ref([]);
const formDialogRef = ref(null);
const deleteDialogRef = ref(null);

const allSelected = computed(
  () =>
    products.value.length > 0 &&
    selectedIds.value.length === products.value.length
);
const someSelected = computed(
  () => selectedIds.value.length > 0 && !allSelected.value
);
const deleteDialogTitle = computed(() => {
  if (deletingIds.value.length === 1) {
    const product = products.value.find(
      item => item.id === deletingIds.value[0]
    );
    return t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE_TITLE', {
      name: product?.name,
    });
  }
  return t('AI_AGENTS.KNOWLEDGE.PRODUCT.BULK_DELETE_TITLE', {
    count: deletingIds.value.length,
  });
});
const deleteDialogDescription = computed(() =>
  deletingIds.value.length === 1
    ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE_DESCRIPTION')
    : t('AI_AGENTS.KNOWLEDGE.PRODUCT.BULK_DELETE_DESCRIPTION')
);

const formatNumber = value => new Intl.NumberFormat(locale.value).format(value);

const fetchProducts = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiAgentKnowledgeAPI.getProducts(
      props.agent.id,
      searchQuery.value.trim()
    );
    products.value = data.payload;
    const ids = new Set(data.payload.map(product => product.id));
    selectedIds.value = selectedIds.value.filter(id => ids.has(id));
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};
const debouncedFetch = debounce(fetchProducts, SEARCH_DEBOUNCE_MS);

const toggleAll = checked => {
  selectedIds.value = checked ? products.value.map(product => product.id) : [];
};

const toggleProduct = (productId, checked) => {
  selectedIds.value = checked
    ? [...selectedIds.value, productId]
    : selectedIds.value.filter(id => id !== productId);
};

const openDeleteDialog = ids => {
  deletingIds.value = ids;
  deleteDialogRef.value.open();
};

const deleteProducts = async () => {
  isDeleting.value = true;
  try {
    if (deletingIds.value.length === 1) {
      await AiAgentKnowledgeAPI.deleteProduct(
        props.agent.id,
        deletingIds.value[0]
      );
    } else {
      await AiAgentKnowledgeAPI.bulkDeleteProducts(
        props.agent.id,
        deletingIds.value
      );
    }
    deleteDialogRef.value.close();
    useAlert(t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE_SUCCESS'));
    await fetchProducts();
    emit('knowledgeChanged');
  } catch {
    useAlert(t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

const onProductSaved = async () => {
  await fetchProducts();
  emit('knowledgeChanged');
};

watch(searchQuery, debouncedFetch);
watch(() => props.agent.id, fetchProducts, { immediate: true });
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <h2 class="text-heading-2 text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.TITLE') }}
      </h2>
      <p class="max-w-3xl text-body-para text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.DESCRIPTION') }}
      </p>
    </header>

    <div class="flex flex-wrap items-center gap-3">
      <label class="flex items-center gap-2 cursor-pointer shrink-0">
        <Checkbox
          :model-value="allSelected"
          :indeterminate="someSelected"
          :disabled="!products.length"
          @update:model-value="toggleAll"
        />
        <span class="text-body-main text-n-blue-11">
          {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.SELECT') }}
        </span>
      </label>
      <Input
        v-model="searchQuery"
        type="search"
        :placeholder="t('AI_AGENTS.KNOWLEDGE.PRODUCT.SEARCH_PLACEHOLDER')"
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
          t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE_SELECTED', {
            count: selectedIds.length,
          })
        "
        icon="i-lucide-trash-2"
        color="ruby"
        variant="faded"
        @click="openDeleteDialog(selectedIds)"
      />
      <Button
        :label="t('AI_AGENTS.KNOWLEDGE.PRODUCT.ADD')"
        icon="i-lucide-package-plus"
        @click="formDialogRef.open()"
      />
    </div>

    <div v-if="isLoading && !products.length" class="flex justify-center py-10">
      <Spinner />
    </div>
    <p
      v-else-if="!products.length"
      class="px-6 py-12 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      {{
        searchQuery
          ? t('AI_AGENTS.KNOWLEDGE.PRODUCT.NO_RESULTS')
          : t('AI_AGENTS.KNOWLEDGE.PRODUCT.EMPTY')
      }}
    </p>
    <ul v-else class="flex flex-col divide-y divide-n-weak">
      <li
        v-for="product in products"
        :key="product.id"
        class="flex flex-wrap items-center gap-x-4 gap-y-2 py-4"
      >
        <Checkbox
          :model-value="selectedIds.includes(product.id)"
          @update:model-value="toggleProduct(product.id, $event)"
        />
        <button
          type="button"
          class="flex items-center flex-1 gap-3 min-w-56 text-start"
          :aria-label="
            t('AI_AGENTS.KNOWLEDGE.PRODUCT.EDIT', { name: product.name })
          "
          @click="formDialogRef.open(product)"
        >
          <span
            class="flex items-center justify-center overflow-hidden rounded-lg size-11 shrink-0 bg-n-alpha-2 text-n-brand"
          >
            <img
              v-if="product.image_url"
              :src="product.image_url"
              alt=""
              class="object-cover size-full"
            />
            <Icon v-else icon="i-lucide-image" class="size-5" />
          </span>
          <span class="flex flex-col min-w-0">
            <span class="truncate text-heading-3 text-n-slate-12">
              {{ product.name }}
            </span>
            <span class="truncate text-body-main text-n-slate-11">
              {{ product.description }}
            </span>
          </span>
        </button>
        <dl
          class="grid grid-cols-3 gap-4 text-body-main tabular-nums sm:w-[26rem]"
        >
          <div class="flex gap-1">
            <dt class="text-n-slate-10">
              {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.WEIGHT') }}
            </dt>
            <dd class="text-n-slate-12">
              {{
                t('AI_AGENTS.KNOWLEDGE.PRODUCT.WEIGHT_VALUE', {
                  weight: formatNumber(product.weight),
                })
              }}
            </dd>
          </div>
          <div class="flex gap-1">
            <dt class="text-n-slate-10">
              {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.STOCK') }}
            </dt>
            <dd class="text-n-slate-12">{{ formatNumber(product.stock) }}</dd>
          </div>
          <div class="flex gap-1">
            <dt class="text-n-slate-10">
              {{ t('AI_AGENTS.KNOWLEDGE.PRODUCT.PRICE') }}
            </dt>
            <dd class="text-n-slate-12">{{ formatNumber(product.price) }}</dd>
          </div>
        </dl>
        <Button
          v-tooltip.top="
            t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE', { name: product.name })
          "
          :aria-label="
            t('AI_AGENTS.KNOWLEDGE.PRODUCT.DELETE', { name: product.name })
          "
          icon="i-lucide-trash-2"
          color="slate"
          variant="ghost"
          size="sm"
          @click="openDeleteDialog([product.id])"
        />
      </li>
    </ul>

    <ProductFormDialog
      ref="formDialogRef"
      :agent-id="agent.id"
      @saved="onProductSaved"
    />
    <ConfirmDeleteDialog
      ref="deleteDialogRef"
      :title="deleteDialogTitle"
      :description="deleteDialogDescription"
      :is-loading="isDeleting"
      @confirm="deleteProducts"
    />
  </section>
</template>
