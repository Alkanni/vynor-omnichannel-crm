# Flow: Captain AI Auto-Response (Enterprise)

Commit `9f920b54`. Status: **VERIFIED** for trigger chain and job entry; LLM/tool internals only located.
Requires `enterprise/` present; licensed separately (`enterprise/LICENSE`).

```mermaid
sequenceDiagram
  participant M as Message (incoming)
  participant H as MessageTemplates::HookExecutionService
  participant EH as Enterprise::MessageTemplates::HookExecutionService (prepended)
  participant RS as Captain::Conversation::ResponseSchedulerService
  participant J as Captain::Conversation::ResponseBuilderJob
  participant LLM as Captain::Llm::AssistantChatService (v1) / Captain::Assistant::AgentRunnerService (v2)
  M->>H: after_create_commit execute_message_template_hooks
  H->>EH: trigger_templates (super → greeting/OOO/email-collect)
  EH->>EH: track_captain_eligibility, return unless conversation.pending?
  EH->>EH: perform_handoff unless inbox.captain_active?
  EH->>RS: perform
  RS->>J: perform_later (delay 1–5s if attachments)
  J->>J: return unless pending, Current.executed_by = assistant
  J->>LLM: generate response (v1 or v2 per feature captain_integration_v2)
  LLM-->>J: response / handoff signal
  J->>M: create outgoing message (→ normal outbound flow) or handoff (conversation → open)
```

## Evidence

| Step | Location |
|---|---|
| Hook entry | `app/models/message.rb:441-443` |
| EE override | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:2-16` |
| Captain active = assistant attached via `captain_inboxes` and more responses allowed (usage limit) | `enterprise/app/models/enterprise/inbox.rb:15-17`; `enterprise/app/models/enterprise/concerns/inbox.rb:5-8` |
| Scheduler & attachment wait | `enterprise/app/services/captain/conversation/response_scheduler_service.rb:1-40` |
| Job, v1/v2 branch, error handoff | `enterprise/app/jobs/captain/conversation/response_builder_job.rb:12-34` and private methods 40-223 |
| Conversation starts `pending` when a bot is active | `app/models/conversation.rb:312-325` |
| Post-resolution memory/FAQ | `enterprise/app/listeners/captain_listener.rb:12-23` |

## Related Captain components (located)

- Models: `enterprise/app/models/captain/{assistant,document,scenario,custom_tool,assistant_response,agent_session,faq_*,message_report}.rb`; tables `captain_*`, `article_embeddings` (pgvector).
- Services: `enterprise/app/services/captain/{llm,tools,assistant,copilot,documents,playground,conversation}`.
- Prompts/schemas: `enterprise/lib/captain/{prompts,*_schema.rb,prompt_renderer.rb}`.
- OSS AI helpers (reply suggestion, summary, rewrite, labels): `lib/captain/*.rb` (some EE-prepended).
- LLM provider/model registry: `config/llm.yml`, `lib/llm/{config,models,feature_router}.rb`.
- Copilot (agent-assist chat): `CopilotThread`, `CopilotMessage`, event `COPILOT_MESSAGE_CREATED` → `Enterprise::ActionCableListener`.

## Unknowns

- Exact tool-calling loop in `AgentRunnerService` and usage/credit accounting not traced.
- `more_responses?` limit source (billing / plan) not traced.
