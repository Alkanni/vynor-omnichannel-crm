<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AiAgentGoogleSheetsAPI from 'dashboard/api/aiAgentGoogleSheets';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SettingsField from '../components/SettingsField.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const WHEN_TO_WRITE_LIMIT = 3000;
const OAUTH_RESULT_PARAM = 'google_sheets';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const sheets = ref(null);
const isLoading = ref(true);
const isConnecting = ref(false);
const isTesting = ref(false);
const isSaving = ref(false);
const isDisconnecting = ref(false);
const testedColumns = ref(null);
const disconnectDialogRef = ref(null);
const form = reactive({
  spreadsheet_url: '',
  sheet_name: '',
  when_to_write: '',
});

const needsReconnect = computed(
  () => sheets.value?.status === 'needs_reconnect'
);
const columns = computed(
  () => testedColumns.value ?? sheets.value?.columns ?? []
);
const namedColumns = computed(() => columns.value.filter(Boolean));
const canTest = computed(
  () => form.spreadsheet_url.trim() && form.sheet_name.trim()
);

const alertError = (error, fallback) => {
  const message = parseAPIErrorResponse(error);
  useAlert(typeof message === 'string' ? message : fallback);
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiAgentGoogleSheetsAPI.get(props.agent.id);
    sheets.value = data;
    testedColumns.value = null;
    form.spreadsheet_url = data.spreadsheet_url || '';
    form.sheet_name = data.sheet_name || '';
    form.when_to_write = data.when_to_write || '';
  } catch (error) {
    alertError(error, t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// Google sends the browser to the Google consent screen, which returns to this page.
const connect = async () => {
  isConnecting.value = true;
  try {
    const { data } = await AiAgentGoogleSheetsAPI.authorize(props.agent.id);
    window.location.href = data.url;
  } catch (error) {
    alertError(error, t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.CONNECT_ERROR'));
    isConnecting.value = false;
  }
};

const sheetParams = () => ({
  spreadsheet_url: form.spreadsheet_url.trim(),
  sheet_name: form.sheet_name.trim(),
});

const testConnection = async () => {
  isTesting.value = true;
  try {
    const { data } = await AiAgentGoogleSheetsAPI.testConnection(
      props.agent.id,
      sheetParams()
    );
    testedColumns.value = data.columns;
    useAlert(t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.TEST_SUCCESS'));
  } catch (error) {
    alertError(error, t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.TEST_ERROR'));
  } finally {
    isTesting.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await AiAgentGoogleSheetsAPI.update(props.agent.id, {
      ...sheetParams(),
      when_to_write: form.when_to_write.trim(),
    });
    sheets.value = data;
    testedColumns.value = null;
    useAlert(t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SAVE_SUCCESS'));
  } catch (error) {
    alertError(error, t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const disconnect = async () => {
  isDisconnecting.value = true;
  try {
    await AiAgentGoogleSheetsAPI.disconnect(props.agent.id);
    disconnectDialogRef.value.close();
    useAlert(t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT_SUCCESS'));
    await load();
  } catch (error) {
    alertError(
      error,
      t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT_ERROR')
    );
  } finally {
    isDisconnecting.value = false;
  }
};

const showOauthResult = () => {
  const result = route.query[OAUTH_RESULT_PARAM];
  if (!result) return;

  useAlert(
    result === 'connected'
      ? t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.CONNECT_SUCCESS')
      : t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.CONNECT_ERROR')
  );
  const query = { ...route.query };
  delete query[OAUTH_RESULT_PARAM];
  router.replace({ query });
};

watch(() => props.agent.id, load);

onMounted(() => {
  showOauthResult();
  load();
});
</script>

<template>
  <div class="h-full overflow-y-auto">
    <div class="flex flex-col w-full max-w-3xl gap-6 px-6 pt-4 pb-10 mx-auto">
      <p class="text-body-main text-n-slate-11">
        {{ t('AI_AGENTS.INTEGRATIONS.DESCRIPTION') }}
      </p>

      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner />
      </div>

      <section
        v-else-if="sheets"
        class="flex flex-col gap-5 p-5 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
      >
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div class="flex items-start gap-3 min-w-0">
            <span
              class="flex items-center justify-center rounded-lg size-10 shrink-0 bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-sheet" class="size-5" />
            </span>
            <div class="flex flex-col gap-1 min-w-0">
              <h2 class="text-heading-2 text-n-slate-12">
                {{ t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.TITLE') }}
              </h2>
              <p class="text-body-main text-n-slate-11">
                {{ t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DESCRIPTION') }}
              </p>
              <p
                v-if="sheets.connected"
                class="text-label-small text-n-slate-11"
              >
                {{
                  t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.CONNECTED_AS', {
                    email: sheets.email,
                  })
                }}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="!sheets.connected || needsReconnect"
              :label="
                needsReconnect
                  ? t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.RECONNECT')
                  : t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.CONNECT')
              "
              icon="i-lucide-link"
              size="sm"
              :is-loading="isConnecting"
              :disabled="!sheets.available || isConnecting"
              @click="connect"
            />
            <Button
              v-if="sheets.connected"
              :label="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT')"
              icon="i-lucide-unlink"
              color="ruby"
              variant="faded"
              size="sm"
              @click="disconnectDialogRef.open()"
            />
          </div>
        </header>

        <Banner v-if="!sheets.available" color="amber">
          {{ t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.UNAVAILABLE') }}
        </Banner>
        <Banner v-if="needsReconnect" color="ruby">
          {{ t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.NEEDS_RECONNECT') }}
        </Banner>

        <form
          v-if="sheets.connected"
          class="flex flex-col gap-6"
          @submit.prevent="save"
        >
          <SettingsField
            :title="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SPREADSHEET.TITLE')"
            :description="
              t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SPREADSHEET.DESCRIPTION')
            "
          >
            <Input
              v-model="form.spreadsheet_url"
              :placeholder="
                t(
                  'AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SPREADSHEET.PLACEHOLDER'
                )
              "
            />
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SHEET_NAME.TITLE')"
            :description="
              t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SHEET_NAME.DESCRIPTION')
            "
          >
            <div class="flex flex-wrap items-center gap-2">
              <Input
                v-model="form.sheet_name"
                class="flex-1 min-w-48"
                :placeholder="
                  t(
                    'AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SHEET_NAME.PLACEHOLDER'
                  )
                "
              />
              <Button
                type="button"
                :label="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.TEST')"
                icon="i-lucide-plug-zap"
                color="slate"
                variant="faded"
                size="sm"
                :is-loading="isTesting"
                :disabled="!canTest || isTesting"
                @click="testConnection"
              />
            </div>
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.COLUMNS.TITLE')"
            :description="
              t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.COLUMNS.DESCRIPTION')
            "
          >
            <div v-if="namedColumns.length" class="flex flex-wrap gap-2">
              <span
                v-for="column in namedColumns"
                :key="column"
                class="px-2 py-0.5 rounded-md text-label-small bg-n-alpha-2 text-n-slate-12"
              >
                {{ column }}
              </span>
            </div>
            <p v-else class="text-label-small text-n-slate-10">
              {{ t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.COLUMNS.EMPTY') }}
            </p>
          </SettingsField>

          <SettingsField
            :title="
              t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.WHEN_TO_WRITE.TITLE')
            "
            :description="
              t(
                'AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.WHEN_TO_WRITE.DESCRIPTION'
              )
            "
          >
            <TextArea
              v-model="form.when_to_write"
              :placeholder="
                t(
                  'AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.WHEN_TO_WRITE.PLACEHOLDER'
                )
              "
              :max-length="WHEN_TO_WRITE_LIMIT"
              show-character-count
              auto-height
            />
          </SettingsField>

          <div class="flex justify-end">
            <Button
              type="submit"
              :label="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.SAVE')"
              :is-loading="isSaving"
              :disabled="!canTest || isSaving"
            />
          </div>
        </form>
      </section>

      <section
        class="flex items-center gap-3 p-5 border border-dashed rounded-xl border-n-weak text-n-slate-11"
      >
        <Icon icon="i-lucide-blocks" class="size-5 shrink-0" />
        <p class="text-body-main">
          {{ t('AI_AGENTS.INTEGRATIONS.COMING_SOON') }}
        </p>
      </section>
    </div>

    <Dialog
      ref="disconnectDialogRef"
      type="alert"
      :title="t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT_DIALOG.TITLE')"
      :description="
        t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT_DIALOG.DESCRIPTION')
      "
      :confirm-button-label="
        t('AI_AGENTS.INTEGRATIONS.GOOGLE_SHEETS.DISCONNECT_DIALOG.CONFIRM')
      "
      :is-loading="isDisconnecting"
      @confirm="disconnect"
    />
  </div>
</template>
