<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const appSecret = ref('');
const isUpdating = ref(false);
const isSecretConfigured = computed(() =>
  Boolean(props.inbox.provider_config?.app_secret)
);

watch(
  () => props.inbox.id,
  () => {
    appSecret.value = '';
  }
);

const updateAppSecret = async () => {
  isUpdating.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        provider_config: {
          ...props.inbox.provider_config,
          app_secret: appSecret.value.trim(),
        },
      },
    });
    appSecret.value = '';
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_TITLE')"
    :help-text="t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_SUBHEADER')"
  >
    <div class="flex flex-col gap-2">
      <div
        v-if="isSecretConfigured"
        class="inline-flex w-fit items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-label-small text-n-teal-11"
      >
        <span class="size-1.5 rounded-full bg-n-teal-9" />
        {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_CONFIGURED') }}
      </div>
      <p v-else class="flex items-start gap-2 text-sm text-n-amber-11">
        <Icon icon="i-lucide-triangle-alert" class="mt-0.5 shrink-0" />
        {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_NOT_CONFIGURED') }}
      </p>
      <div class="flex flex-1 justify-between items-center">
        <woot-input
          v-model="appSecret"
          type="password"
          autocomplete="off"
          class="flex-1 me-2 [&>input]:!mb-0"
          :placeholder="
            t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_PLACEHOLDER')
          "
        />
        <NextButton
          :disabled="!appSecret.trim() || isUpdating"
          :is-loading="isUpdating"
          @click="updateAppSecret"
        >
          {{
            isSecretConfigured
              ? t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_REPLACE_BUTTON'
                )
              : t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_SECRET_ADD_BUTTON')
          }}
        </NextButton>
      </div>
    </div>
  </SettingsFieldSection>
</template>
