<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useIntervalFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { timeZoneOptions } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import AiAgentsAPI from 'dashboard/api/aiAgents';

import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AiAgentPlayground from '../components/AiAgentPlayground.vue';
import CollapsiblePanel from '../components/CollapsiblePanel.vue';
import SettingsField from '../components/SettingsField.vue';
import ToggleField from '../components/ToggleField.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const TRAINING_POLL_INTERVAL = 5000;
const TRAINING_POLL_ATTEMPTS = 24;
const TEXT_LIMITS = {
  behavior: 15000,
  welcomeMessage: 5000,
  transferConditions: 3000,
  pendingMessage: 200,
  labelConditions: 3000,
  bookingConditions: 3000,
  bookingMessage: 5000,
  scopePolicy: 3000,
  scopeReply: 1000,
  webSearchDomains: 1000,
};
// The booking variables a booking template can use (see BookingDrop). The summary shows a booking that is not recorded
// yet, so it has no id.
const BOOKING_MESSAGE_VARIABLES = {
  name: '{{booking.customer_name}}',
  service: '{{booking.service}}',
  date: '{{booking.date}}',
  time: '{{booking.time}}',
  notes: '{{booking.notes}}',
  extraFields: '{{booking.extra_fields}}',
  id: '{{booking.id}}',
};
const BOOKING_SUMMARY_VARIABLES = Object.values(BOOKING_MESSAGE_VARIABLES)
  .filter(variable => variable !== BOOKING_MESSAGE_VARIABLES.id)
  .join(', ');
const BOOKING_DETAIL_VARIABLE = '{{booking.details["Plate number"]}}';

const { t } = useI18n();
const store = useStore();
const { isCloudFeatureEnabled } = useAccount();

const labels = useMapGetter('labels/getLabels');
const inboxes = useMapGetter('inboxes/getInboxes');

const toForm = agent => ({
  name: agent.name,
  inbox_ids: [...agent.inbox_ids],
  behavior: agent.behavior || '',
  welcome_message: agent.welcome_message || '',
  transfer_conditions: agent.transfer_conditions || '',
  stop_ai_after_handoff: agent.stop_ai_after_handoff,
  silent_handoff: agent.silent_handoff,
  pending_assigned_message: agent.pending_assigned_message || '',
  pending_unassigned_message: agent.pending_unassigned_message || '',
  allowed_label_ids: [...agent.allowed_label_ids],
  label_conditions: agent.label_conditions || '',
  model: agent.model,
  history_limit: agent.history_limit,
  read_file_limit: agent.read_file_limit,
  context_limit: agent.context_limit,
  context_expansion_radius: agent.context_expansion_radius,
  temperature: agent.temperature,
  message_await: agent.message_await,
  message_limit: agent.message_limit,
  watcher_enabled: agent.watcher_enabled,
  timezone: agent.timezone,
  session_only_memory: agent.session_only_memory,
  ignore_team_handoff: agent.ignore_team_handoff,
  scope_mode: agent.scope_mode,
  business_description: agent.business_description || '',
  allowed_topics: agent.allowed_topics || '',
  disallowed_topics: agent.disallowed_topics || '',
  off_topic_message: agent.off_topic_message || '',
  clarification_message: agent.clarification_message || '',
  knowledge_gap_message: agent.knowledge_gap_message || '',
  web_search_enabled: agent.web_search_enabled,
  web_search_domains: agent.web_search_domains || '',
  booking_enabled: agent.booking_enabled,
  booking_conditions: agent.booking_conditions || '',
  booking_label_id: agent.booking_label_id,
  booking_fields: [...agent.booking_fields],
  booking_confirmed_message: agent.booking_confirmed_message || '',
  booking_cancelled_message: agent.booking_cancelled_message || '',
  booking_summary_template: agent.booking_summary_template || '',
});

const form = reactive(toForm(props.agent));
const savedForm = ref(toForm(props.agent));
const isSaving = ref(false);
const availableModels = ref([]);

const labelOptions = computed(() =>
  labels.value.map(label => ({ value: label.id, label: label.title }))
);
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const existingLabelIds = computed(
  () => new Set(labels.value.map(label => label.id))
);
// Labels deleted from the account are dropped instead of failing validation.
const existingLabelsOnly = ids =>
  ids.filter(id => existingLabelIds.value.has(id));
const selectedLabelIds = computed({
  get: () => existingLabelsOnly(form.allowed_label_ids),
  set: ids => {
    form.allowed_label_ids = ids;
  },
});
// Bookings need the account feature; the agent setting alone records none (see AiAgent#booking?).
const isBookingFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.BOOKINGS)
);
// A deleted booking label is sent as none, so saving asks for a new one.
const existingLabelOrNull = id => (existingLabelIds.value.has(id) ? id : null);
const bookingMessageVariables = Object.values(BOOKING_MESSAGE_VARIABLES).join(
  ', '
);
// A starter summary in the interface language for the admin to edit; the extra fields and the notes get a line only when
// they have a value.
const fillStarterSummaryTemplate = () => {
  const { name, service, date, time, notes, extraFields } =
    BOOKING_MESSAGE_VARIABLES;
  const notesLabel = t(
    'AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.NOTES'
  );
  form.booking_summary_template = [
    t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.TITLE'),
    `${t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.NAME')}: ${name}`,
    `${t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.SERVICE')}: ${service}`,
    `${t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.DATE')}: ${date}`,
    `${t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.TIME')}: ${time}`,
    `{% if booking.extra_fields != blank %}${extraFields}\n{% endif %}` +
      `{% if booking.notes != blank %}${notesLabel}: ${notes}\n{% endif %}`,
    t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER.CONFIRM'),
  ].join('\n');
};

const modelOptions = computed(() => {
  const options = availableModels.value.map(model => ({
    value: model.id,
    label: model.display_name,
  }));
  if (options.some(option => option.value === form.model)) return options;

  return [{ value: form.model, label: form.model }, ...options];
});
const temperatureOptions = computed(() => [
  {
    value: 'precise',
    label: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TEMPERATURE.OPTIONS.PRECISE'
    ),
  },
  {
    value: 'balanced',
    label: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TEMPERATURE.OPTIONS.BALANCED'
    ),
  },
  {
    value: 'creative',
    label: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TEMPERATURE.OPTIONS.CREATIVE'
    ),
  },
]);
const scopeModeOptions = computed(() => [
  {
    value: 'off',
    label: t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.MODE.OPTIONS.OFF'),
  },
  {
    value: 'strict',
    label: t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.MODE.OPTIONS.STRICT'),
  },
]);
const memoryFields = computed(() => [
  {
    key: 'history_limit',
    min: 1,
    max: 100,
    title: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.HISTORY_LIMIT.TITLE'),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.HISTORY_LIMIT.DESCRIPTION'
    ),
  },
  {
    key: 'read_file_limit',
    min: 0,
    max: 10,
    title: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.READ_FILE_LIMIT.TITLE'),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.READ_FILE_LIMIT.DESCRIPTION'
    ),
  },
  {
    key: 'context_limit',
    min: 1,
    max: 100,
    title: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.CONTEXT_LIMIT.TITLE'),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.CONTEXT_LIMIT.DESCRIPTION'
    ),
  },
  {
    key: 'context_expansion_radius',
    min: 0,
    max: 3,
    title: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.CONTEXT_EXPANSION_RADIUS.TITLE'
    ),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.CONTEXT_EXPANSION_RADIUS.DESCRIPTION'
    ),
  },
]);
const timingFields = computed(() => [
  {
    key: 'message_await',
    min: 0,
    max: 300,
    title: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.MESSAGE_AWAIT.TITLE'),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.MESSAGE_AWAIT.DESCRIPTION'
    ),
  },
  {
    key: 'message_limit',
    min: 1,
    max: 1000,
    title: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.MESSAGE_LIMIT.TITLE'),
    description: t(
      'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.MESSAGE_LIMIT.DESCRIPTION'
    ),
  },
]);
const switchOptions = computed(() => [
  { value: 'off', label: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.OFF') },
  { value: 'on', label: t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.ON') },
]);
const timezoneOptions = timeZoneOptions();

const booleanSelect = key =>
  computed({
    get: () => (form[key] ? 'on' : 'off'),
    set: value => {
      if (value) form[key] = value === 'on';
    },
  });
const watcherSelect = booleanSelect('watcher_enabled');
const sessionOnlyMemorySelect = booleanSelect('session_only_memory');

// ComboBox emits an empty value when the selected option is clicked again;
// these fields always need a value, so that click is ignored.
const setRequired = (key, value) => {
  if (value) form[key] = value;
};

// Web search needs Strict mode, so turning Strict off also turns it off.
const setScopeMode = value => {
  setRequired('scope_mode', value);
  if (form.scope_mode !== 'strict') form.web_search_enabled = false;
};

const toPayload = values => ({
  ...values,
  name: values.name.trim(),
  allowed_label_ids: existingLabelsOnly(values.allowed_label_ids),
  booking_label_id: existingLabelOrNull(values.booking_label_id),
});
const payload = computed(() => toPayload(form));
const isDirty = computed(
  () =>
    JSON.stringify(payload.value) !== JSON.stringify(toPayload(savedForm.value))
);

const resetForm = agent => {
  Object.assign(form, toForm(agent));
  savedForm.value = toForm(agent);
};

const rangeHint = ({ min, max }) =>
  t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.RANGE', { min, max });

const saveSettings = async () => {
  isSaving.value = true;
  try {
    const agent = await store.dispatch('aiAgents/update', {
      id: props.agent.id,
      ...payload.value,
    });
    resetForm(agent);
    useAlert(t('AI_AGENTS.GENERAL.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('AI_AGENTS.GENERAL.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const lastTrainedLabel = computed(() =>
  props.agent.trained_at
    ? t('AI_AGENTS.GENERAL.TRAINING.LAST_TRAINED', {
        time: dynamicTime(props.agent.trained_at),
      })
    : t('AI_AGENTS.GENERAL.TRAINING.NEVER_TRAINED')
);

// After Train, the agent is refreshed until the indexing job records a new training time.
let trainingPollAttempts = 0;
let trainedAtBeforeTraining = null;
const { pause: stopTrainingPoll, resume: startTrainingPoll } = useIntervalFn(
  async () => {
    trainingPollAttempts += 1;
    try {
      const agent = await store.dispatch('aiAgents/show', props.agent.id);
      if (
        agent.trained_at !== trainedAtBeforeTraining ||
        trainingPollAttempts >= TRAINING_POLL_ATTEMPTS
      ) {
        stopTrainingPoll();
      }
    } catch {
      stopTrainingPoll();
    }
  },
  TRAINING_POLL_INTERVAL,
  { immediate: false }
);
const isTraining = ref(false);

const train = async () => {
  isTraining.value = true;
  try {
    await AiAgentsAPI.train(props.agent.id);
    useAlert(t('AI_AGENTS.GENERAL.TRAINING.TRAIN_SUCCESS'));
    trainingPollAttempts = 0;
    trainedAtBeforeTraining = props.agent.trained_at;
    startTrainingPoll();
  } catch {
    useAlert(t('AI_AGENTS.GENERAL.TRAINING.TRAIN_ERROR'));
  } finally {
    isTraining.value = false;
  }
};

watch(
  () => props.agent.id,
  () => {
    stopTrainingPoll();
    resetForm(props.agent);
  }
);

onMounted(async () => {
  // Without the list, the model dropdown still shows the agent's current model.
  AiAgentsAPI.getModels()
    .then(({ data }) => {
      availableModels.value = data.models;
    })
    .catch(() => {});
  // Knowledge edits on the other tab retrain the agent, so the training time is refreshed here.
  try {
    await store.dispatch('aiAgents/show', props.agent.id);
  } catch {
    // The detail page reports an agent that no longer exists.
  }
});
</script>

<template>
  <div class="flex h-full">
    <div class="flex flex-col flex-1 min-w-0 h-full">
      <div class="flex-1 min-h-0 overflow-y-auto">
        <div class="flex flex-col w-full max-w-3xl gap-4 px-6 pt-4 mx-auto">
          <Banner v-if="!agent.llm_configured" color="amber">
            {{ t('AI_AGENTS.GENERAL.LLM_NOT_CONFIGURED') }}
          </Banner>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <span class="text-body-main text-n-slate-11">
              {{ lastTrainedLabel }}
            </span>
            <Button
              :label="t('AI_AGENTS.GENERAL.TRAINING.TRAIN')"
              icon="i-lucide-refresh-cw"
              color="slate"
              variant="faded"
              size="sm"
              :is-loading="isTraining"
              :disabled="!agent.llm_configured || isTraining"
              @click="train"
            />
          </div>
        </div>
        <form
          id="ai-agent-general-form"
          class="flex flex-col w-full max-w-3xl gap-8 px-6 pt-4 pb-10 mx-auto"
          @submit.prevent="saveSettings"
        >
          <SettingsField :title="t('AI_AGENTS.GENERAL.NAME.TITLE')">
            <Input
              id="ai-agent-name"
              v-model="form.name"
              :placeholder="t('AI_AGENTS.GENERAL.NAME.PLACEHOLDER')"
            />
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.GENERAL.CONNECTED_INBOXES.TITLE')"
            :description="t('AI_AGENTS.GENERAL.CONNECTED_INBOXES.DESCRIPTION')"
          >
            <TagMultiSelectComboBox
              v-model="form.inbox_ids"
              :options="inboxOptions"
              :placeholder="
                t('AI_AGENTS.GENERAL.CONNECTED_INBOXES.PLACEHOLDER')
              "
              :search-placeholder="
                t('AI_AGENTS.GENERAL.CONNECTED_INBOXES.SEARCH_PLACEHOLDER')
              "
              :empty-state="t('AI_AGENTS.GENERAL.CONNECTED_INBOXES.EMPTY')"
            />
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.GENERAL.BEHAVIOR.TITLE')"
            :description="t('AI_AGENTS.GENERAL.BEHAVIOR.DESCRIPTION')"
          >
            <TextArea
              id="ai-agent-behavior"
              v-model="form.behavior"
              :placeholder="t('AI_AGENTS.GENERAL.BEHAVIOR.PLACEHOLDER')"
              :max-length="TEXT_LIMITS.behavior"
              show-character-count
              auto-height
              resize
              min-height="10rem"
              max-height="28rem"
            />
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.GENERAL.WELCOME_MESSAGE.TITLE')"
            :description="t('AI_AGENTS.GENERAL.WELCOME_MESSAGE.DESCRIPTION')"
          >
            <TextArea
              id="ai-agent-welcome-message"
              v-model="form.welcome_message"
              :placeholder="t('AI_AGENTS.GENERAL.WELCOME_MESSAGE.PLACEHOLDER')"
              :max-length="TEXT_LIMITS.welcomeMessage"
              show-character-count
              auto-height
              resize
              min-height="5rem"
            />
          </SettingsField>

          <SettingsField
            :title="t('AI_AGENTS.GENERAL.TRANSFER_CONDITIONS.TITLE')"
            :description="
              t('AI_AGENTS.GENERAL.TRANSFER_CONDITIONS.DESCRIPTION')
            "
          >
            <TextArea
              id="ai-agent-transfer-conditions"
              v-model="form.transfer_conditions"
              :placeholder="
                t('AI_AGENTS.GENERAL.TRANSFER_CONDITIONS.PLACEHOLDER')
              "
              :max-length="TEXT_LIMITS.transferConditions"
              show-character-count
              auto-height
              resize
              min-height="5rem"
            />
          </SettingsField>

          <CollapsiblePanel
            icon="i-lucide-shield-check"
            :title="t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.TITLE')"
            :description="t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.DESCRIPTION')"
          >
            <SettingsField
              :title="t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.MODE.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.MODE.DESCRIPTION')
              "
            >
              <ComboBox
                :model-value="form.scope_mode"
                :options="scopeModeOptions"
                @update:model-value="setScopeMode"
              />
            </SettingsField>
            <SettingsField
              :title="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.BUSINESS_DESCRIPTION.TITLE')
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.BUSINESS_DESCRIPTION.DESCRIPTION'
                )
              "
            >
              <TextArea
                id="ai-agent-business-description"
                v-model="form.business_description"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.BUSINESS_DESCRIPTION.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopePolicy"
                show-character-count
                auto-height
                resize
                min-height="5rem"
              />
            </SettingsField>
            <SettingsField
              :title="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.ALLOWED_TOPICS.TITLE')
              "
              :description="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.ALLOWED_TOPICS.DESCRIPTION')
              "
            >
              <TextArea
                id="ai-agent-allowed-topics"
                v-model="form.allowed_topics"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.ALLOWED_TOPICS.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopePolicy"
                show-character-count
                auto-height
                resize
                min-height="5rem"
              />
            </SettingsField>
            <SettingsField
              :title="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.DISALLOWED_TOPICS.TITLE')
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.DISALLOWED_TOPICS.DESCRIPTION'
                )
              "
            >
              <TextArea
                id="ai-agent-disallowed-topics"
                v-model="form.disallowed_topics"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.DISALLOWED_TOPICS.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopePolicy"
                show-character-count
                auto-height
                resize
                min-height="5rem"
              />
            </SettingsField>
            <SettingsField
              :title="
                t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.OFF_TOPIC_MESSAGE.TITLE')
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.OFF_TOPIC_MESSAGE.DESCRIPTION'
                )
              "
            >
              <TextArea
                id="ai-agent-off-topic-message"
                v-model="form.off_topic_message"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.OFF_TOPIC_MESSAGE.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopeReply"
                show-character-count
                auto-height
                resize
                min-height="3rem"
              />
            </SettingsField>
            <SettingsField
              :title="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.CLARIFICATION_MESSAGE.TITLE'
                )
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.CLARIFICATION_MESSAGE.DESCRIPTION'
                )
              "
            >
              <TextArea
                id="ai-agent-clarification-message"
                v-model="form.clarification_message"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.CLARIFICATION_MESSAGE.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopeReply"
                show-character-count
                auto-height
                resize
                min-height="3rem"
              />
            </SettingsField>
            <SettingsField
              :title="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.KNOWLEDGE_GAP_MESSAGE.TITLE'
                )
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.BUSINESS_SCOPE.KNOWLEDGE_GAP_MESSAGE.DESCRIPTION'
                )
              "
            >
              <TextArea
                id="ai-agent-knowledge-gap-message"
                v-model="form.knowledge_gap_message"
                :placeholder="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.KNOWLEDGE_GAP_MESSAGE.PLACEHOLDER'
                  )
                "
                :max-length="TEXT_LIMITS.scopeReply"
                show-character-count
                auto-height
                resize
                min-height="3rem"
              />
            </SettingsField>
            <template v-if="form.scope_mode === 'strict'">
              <ToggleField
                v-model="form.web_search_enabled"
                :title="t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.WEB_SEARCH.TITLE')"
                :description="
                  t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.WEB_SEARCH.DESCRIPTION')
                "
              />
              <SettingsField
                v-if="form.web_search_enabled"
                :title="
                  t('AI_AGENTS.GENERAL.BUSINESS_SCOPE.WEB_SEARCH_DOMAINS.TITLE')
                "
                :description="
                  t(
                    'AI_AGENTS.GENERAL.BUSINESS_SCOPE.WEB_SEARCH_DOMAINS.DESCRIPTION'
                  )
                "
              >
                <TextArea
                  id="ai-agent-web-search-domains"
                  v-model="form.web_search_domains"
                  :placeholder="
                    t(
                      'AI_AGENTS.GENERAL.BUSINESS_SCOPE.WEB_SEARCH_DOMAINS.PLACEHOLDER'
                    )
                  "
                  :max-length="TEXT_LIMITS.webSearchDomains"
                  show-character-count
                  auto-height
                  resize
                  min-height="3rem"
                />
              </SettingsField>
            </template>
          </CollapsiblePanel>

          <div class="flex flex-col gap-5">
            <ToggleField
              v-model="form.stop_ai_after_handoff"
              :title="t('AI_AGENTS.GENERAL.STOP_AI_AFTER_HANDOFF.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.STOP_AI_AFTER_HANDOFF.DESCRIPTION')
              "
            />
            <ToggleField
              v-model="form.silent_handoff"
              :title="t('AI_AGENTS.GENERAL.SILENT_HANDOFF.TITLE')"
              :description="t('AI_AGENTS.GENERAL.SILENT_HANDOFF.DESCRIPTION')"
            />
          </div>

          <CollapsiblePanel
            icon="i-lucide-clock"
            :title="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.TITLE')"
            :description="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.DESCRIPTION')"
          >
            <SettingsField
              :title="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.ASSIGNED.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.PENDING_MESSAGES.ASSIGNED.DESCRIPTION')
              "
              :badge="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.ASSIGNED.BADGE')"
            >
              <TextArea
                id="ai-agent-pending-assigned-message"
                v-model="form.pending_assigned_message"
                :placeholder="
                  t('AI_AGENTS.GENERAL.PENDING_MESSAGES.ASSIGNED.PLACEHOLDER')
                "
                :max-length="TEXT_LIMITS.pendingMessage"
                show-character-count
              />
            </SettingsField>
            <SettingsField
              :title="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.UNASSIGNED.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.PENDING_MESSAGES.UNASSIGNED.DESCRIPTION')
              "
              :badge="t('AI_AGENTS.GENERAL.PENDING_MESSAGES.UNASSIGNED.BADGE')"
            >
              <TextArea
                id="ai-agent-pending-unassigned-message"
                v-model="form.pending_unassigned_message"
                :placeholder="
                  t('AI_AGENTS.GENERAL.PENDING_MESSAGES.UNASSIGNED.PLACEHOLDER')
                "
                :max-length="TEXT_LIMITS.pendingMessage"
                show-character-count
              />
            </SettingsField>
          </CollapsiblePanel>

          <CollapsiblePanel
            icon="i-lucide-zap"
            :title="t('AI_AGENTS.GENERAL.AI_ACTIONS.TITLE')"
            :description="t('AI_AGENTS.GENERAL.AI_ACTIONS.DESCRIPTION')"
          >
            <SettingsField
              :title="t('AI_AGENTS.GENERAL.AI_ACTIONS.LABELS.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.AI_ACTIONS.LABELS.DESCRIPTION')
              "
            >
              <TagMultiSelectComboBox
                v-model="selectedLabelIds"
                :options="labelOptions"
                :placeholder="
                  t('AI_AGENTS.GENERAL.AI_ACTIONS.LABELS.PLACEHOLDER')
                "
                :search-placeholder="
                  t('AI_AGENTS.GENERAL.AI_ACTIONS.LABELS.SEARCH_PLACEHOLDER')
                "
                :empty-state="t('AI_AGENTS.GENERAL.AI_ACTIONS.LABELS.EMPTY')"
              />
            </SettingsField>
            <SettingsField
              :title="t('AI_AGENTS.GENERAL.AI_ACTIONS.LABEL_CONDITIONS.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.AI_ACTIONS.LABEL_CONDITIONS.DESCRIPTION')
              "
            >
              <TextArea
                id="ai-agent-label-conditions"
                v-model="form.label_conditions"
                :placeholder="
                  t('AI_AGENTS.GENERAL.AI_ACTIONS.LABEL_CONDITIONS.PLACEHOLDER')
                "
                :max-length="TEXT_LIMITS.labelConditions"
                show-character-count
                auto-height
                resize
                min-height="5rem"
              />
            </SettingsField>
          </CollapsiblePanel>

          <CollapsiblePanel
            v-if="isBookingFeatureEnabled"
            icon="i-lucide-calendar-check"
            :title="t('AI_AGENTS.GENERAL.BOOKING.TITLE')"
            :description="t('AI_AGENTS.GENERAL.BOOKING.DESCRIPTION')"
          >
            <ToggleField
              v-model="form.booking_enabled"
              :title="t('AI_AGENTS.GENERAL.BOOKING.ENABLED.TITLE')"
              :description="t('AI_AGENTS.GENERAL.BOOKING.ENABLED.DESCRIPTION')"
            />
            <template v-if="form.booking_enabled">
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.CONDITIONS.TITLE')"
                :description="
                  t('AI_AGENTS.GENERAL.BOOKING.CONDITIONS.DESCRIPTION')
                "
              >
                <TextArea
                  id="ai-agent-booking-conditions"
                  v-model="form.booking_conditions"
                  :placeholder="
                    t('AI_AGENTS.GENERAL.BOOKING.CONDITIONS.PLACEHOLDER')
                  "
                  :max-length="TEXT_LIMITS.bookingConditions"
                  show-character-count
                  auto-height
                  resize
                  min-height="5rem"
                />
              </SettingsField>
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.LABEL.TITLE')"
                :description="t('AI_AGENTS.GENERAL.BOOKING.LABEL.DESCRIPTION')"
              >
                <ComboBox
                  v-model="form.booking_label_id"
                  :options="labelOptions"
                  :placeholder="
                    t('AI_AGENTS.GENERAL.BOOKING.LABEL.PLACEHOLDER')
                  "
                  :search-placeholder="
                    t('AI_AGENTS.GENERAL.BOOKING.LABEL.SEARCH_PLACEHOLDER')
                  "
                  :empty-state="t('AI_AGENTS.GENERAL.BOOKING.LABEL.EMPTY')"
                />
              </SettingsField>
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.TITLE')"
                :description="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.DESCRIPTION')"
              >
                <TagInput
                  v-model="form.booking_fields"
                  :placeholder="
                    t('AI_AGENTS.GENERAL.BOOKING.FIELDS.PLACEHOLDER')
                  "
                />
              </SettingsField>
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.TITLE')"
                :description="
                  t('AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.DESCRIPTION', {
                    variables: BOOKING_SUMMARY_VARIABLES,
                    detail: BOOKING_DETAIL_VARIABLE,
                  })
                "
              >
                <TextArea
                  id="ai-agent-booking-summary-template"
                  v-model="form.booking_summary_template"
                  :placeholder="
                    t(
                      'AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.PLACEHOLDER',
                      BOOKING_MESSAGE_VARIABLES
                    )
                  "
                  :max-length="TEXT_LIMITS.bookingMessage"
                  show-character-count
                  auto-height
                  resize
                  min-height="5rem"
                />
                <Button
                  v-if="!form.booking_summary_template"
                  type="button"
                  :label="
                    t(
                      'AI_AGENTS.GENERAL.BOOKING.SUMMARY_TEMPLATE.STARTER_BUTTON'
                    )
                  "
                  icon="i-lucide-file-text"
                  color="slate"
                  variant="faded"
                  size="sm"
                  class="self-start"
                  @click="fillStarterSummaryTemplate"
                />
              </SettingsField>
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.CONFIRMED_MESSAGE.TITLE')"
                :description="
                  t('AI_AGENTS.GENERAL.BOOKING.CONFIRMED_MESSAGE.DESCRIPTION', {
                    variables: bookingMessageVariables,
                  })
                "
              >
                <TextArea
                  id="ai-agent-booking-confirmed-message"
                  v-model="form.booking_confirmed_message"
                  :placeholder="
                    t(
                      'AI_AGENTS.GENERAL.BOOKING.CONFIRMED_MESSAGE.PLACEHOLDER',
                      BOOKING_MESSAGE_VARIABLES
                    )
                  "
                  :max-length="TEXT_LIMITS.bookingMessage"
                  show-character-count
                  auto-height
                  resize
                  min-height="5rem"
                />
              </SettingsField>
              <SettingsField
                :title="t('AI_AGENTS.GENERAL.BOOKING.CANCELLED_MESSAGE.TITLE')"
                :description="
                  t('AI_AGENTS.GENERAL.BOOKING.CANCELLED_MESSAGE.DESCRIPTION', {
                    variables: bookingMessageVariables,
                  })
                "
              >
                <TextArea
                  id="ai-agent-booking-cancelled-message"
                  v-model="form.booking_cancelled_message"
                  :placeholder="
                    t(
                      'AI_AGENTS.GENERAL.BOOKING.CANCELLED_MESSAGE.PLACEHOLDER',
                      BOOKING_MESSAGE_VARIABLES
                    )
                  "
                  :max-length="TEXT_LIMITS.bookingMessage"
                  show-character-count
                  auto-height
                  resize
                  min-height="5rem"
                />
              </SettingsField>
              <p class="text-label-small text-n-slate-11">
                {{ t('AI_AGENTS.GENERAL.BOOKING.MESSAGE_WINDOW') }}
              </p>
            </template>
          </CollapsiblePanel>

          <SettingsField
            :title="t('AI_AGENTS.GENERAL.AI_MODEL.TITLE')"
            :description="t('AI_AGENTS.GENERAL.AI_MODEL.DESCRIPTION')"
          >
            <ComboBox
              :model-value="form.model"
              :options="modelOptions"
              :search-placeholder="
                t('AI_AGENTS.GENERAL.AI_MODEL.SEARCH_PLACEHOLDER')
              "
              @update:model-value="setRequired('model', $event)"
            />
          </SettingsField>

          <CollapsiblePanel
            icon="i-lucide-sliders-horizontal"
            :title="t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TITLE')"
            :description="
              t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.DESCRIPTION')
            "
          >
            <SettingsField
              v-for="field in memoryFields"
              :key="field.key"
              :title="field.title"
              :description="field.description"
            >
              <Input
                :id="`ai-agent-${field.key}`"
                v-model="form[field.key]"
                type="number"
                :min="String(field.min)"
                :max="String(field.max)"
                :message="rangeHint(field)"
              />
            </SettingsField>

            <SettingsField
              :title="
                t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TEMPERATURE.TITLE')
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TEMPERATURE.DESCRIPTION'
                )
              "
            >
              <ComboBox
                :model-value="form.temperature"
                :options="temperatureOptions"
                @update:model-value="setRequired('temperature', $event)"
              />
            </SettingsField>

            <SettingsField
              v-for="field in timingFields"
              :key="field.key"
              :title="field.title"
              :description="field.description"
            >
              <Input
                :id="`ai-agent-${field.key}`"
                v-model="form[field.key]"
                type="number"
                :min="String(field.min)"
                :max="String(field.max)"
                :message="rangeHint(field)"
              />
            </SettingsField>

            <SettingsField
              :title="t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.WATCHER.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.WATCHER.DESCRIPTION')
              "
            >
              <ComboBox v-model="watcherSelect" :options="switchOptions" />
            </SettingsField>

            <SettingsField
              :title="t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TIMEZONE.TITLE')"
              :description="
                t('AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TIMEZONE.DESCRIPTION')
              "
            >
              <ComboBox
                :model-value="form.timezone"
                :options="timezoneOptions"
                :search-placeholder="
                  t(
                    'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.TIMEZONE.SEARCH_PLACEHOLDER'
                  )
                "
                :display-label="form.timezone"
                @update:model-value="setRequired('timezone', $event)"
              />
            </SettingsField>

            <SettingsField
              :title="
                t(
                  'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.SESSION_ONLY_MEMORY.TITLE'
                )
              "
              :description="
                t(
                  'AI_AGENTS.GENERAL.ADDITIONAL_SETTINGS.SESSION_ONLY_MEMORY.DESCRIPTION'
                )
              "
            >
              <ComboBox
                v-model="sessionOnlyMemorySelect"
                :options="switchOptions"
              />
            </SettingsField>
          </CollapsiblePanel>

          <ToggleField
            v-model="form.ignore_team_handoff"
            :title="t('AI_AGENTS.GENERAL.IGNORE_TEAM_HANDOFF.TITLE')"
            :description="
              t('AI_AGENTS.GENERAL.IGNORE_TEAM_HANDOFF.DESCRIPTION')
            "
          />
        </form>
      </div>

      <footer
        class="flex justify-center px-6 py-3 border-t border-n-weak bg-n-surface-1"
      >
        <Button
          type="submit"
          form="ai-agent-general-form"
          :label="t('AI_AGENTS.GENERAL.SAVE')"
          :disabled="!isDirty || isSaving"
          :is-loading="isSaving"
        />
      </footer>
    </div>

    <aside
      class="hidden lg:flex flex-col w-96 shrink-0 border-s border-n-weak bg-n-surface-1"
    >
      <AiAgentPlayground :agent-id="agent.id" />
    </aside>
  </div>
</template>
