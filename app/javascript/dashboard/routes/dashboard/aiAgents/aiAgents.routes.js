import { frontendURL } from '../../../helper/URLHelper';
import AiAgentsIndexPage from './pages/AiAgentsIndexPage.vue';
import AiAgentDetailPage from './pages/AiAgentDetailPage.vue';
import AiAgentGeneralPage from './pages/AiAgentGeneralPage.vue';
import KnowledgeSourcesPage from './pages/KnowledgeSourcesPage.vue';
import AiAgentIntegrationsPage from './pages/AiAgentIntegrationsPage.vue';
import KnowledgeTextPage from './pages/knowledge/KnowledgeTextPage.vue';
import KnowledgeWebsitePage from './pages/knowledge/KnowledgeWebsitePage.vue';
import KnowledgeFilePage from './pages/knowledge/KnowledgeFilePage.vue';
import KnowledgeQaPage from './pages/knowledge/KnowledgeQaPage.vue';
import KnowledgeProductsPage from './pages/knowledge/KnowledgeProductsPage.vue';
import KnowledgePromotionsPage from './pages/knowledge/KnowledgePromotionsPage.vue';

const meta = {
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai-agents'),
    name: 'ai_agents_index',
    component: AiAgentsIndexPage,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/ai-agents/:agentId'),
    component: AiAgentDetailPage,
    meta,
    children: [
      {
        path: '',
        name: 'ai_agents_show',
        meta,
        redirect: to => ({ name: 'ai_agents_general', params: to.params }),
      },
      {
        path: 'general',
        name: 'ai_agents_general',
        component: AiAgentGeneralPage,
        meta,
      },
      {
        path: 'knowledge-sources',
        name: 'ai_agents_knowledge',
        component: KnowledgeSourcesPage,
        meta,
        redirect: to => ({
          name: 'ai_agents_knowledge_text',
          params: to.params,
        }),
        children: [
          {
            path: 'text',
            name: 'ai_agents_knowledge_text',
            component: KnowledgeTextPage,
            meta,
          },
          {
            path: 'website',
            name: 'ai_agents_knowledge_website',
            component: KnowledgeWebsitePage,
            meta,
          },
          {
            path: 'file',
            name: 'ai_agents_knowledge_file',
            component: KnowledgeFilePage,
            meta,
          },
          {
            path: 'qa',
            name: 'ai_agents_knowledge_qa',
            component: KnowledgeQaPage,
            meta,
          },
          {
            path: 'products',
            name: 'ai_agents_knowledge_products',
            component: KnowledgeProductsPage,
            meta,
          },
          {
            path: 'promotions',
            name: 'ai_agents_knowledge_promotions',
            component: KnowledgePromotionsPage,
            meta,
          },
        ],
      },
      {
        path: 'integrations',
        name: 'ai_agents_integrations',
        component: AiAgentIntegrationsPage,
        meta,
      },
    ],
  },
];
