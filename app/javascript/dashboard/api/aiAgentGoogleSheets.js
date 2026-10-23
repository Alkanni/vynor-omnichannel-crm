/* global axios */
import ApiClient from './ApiClient';

class AiAgentGoogleSheetsAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  sheetsUrl(agentId) {
    return `${this.url}/${agentId}/google_sheets`;
  }

  get(agentId) {
    return axios.get(this.sheetsUrl(agentId));
  }

  authorize(agentId) {
    return axios.post(`${this.sheetsUrl(agentId)}/authorization`);
  }

  testConnection(agentId, data) {
    return axios.post(`${this.sheetsUrl(agentId)}/test_connection`, data);
  }

  update(agentId, data) {
    return axios.patch(this.sheetsUrl(agentId), data);
  }

  disconnect(agentId) {
    return axios.delete(this.sheetsUrl(agentId));
  }
}

export default new AiAgentGoogleSheetsAPI();
