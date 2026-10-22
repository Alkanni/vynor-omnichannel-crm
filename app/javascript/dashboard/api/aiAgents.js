/* global axios */
import ApiClient from './ApiClient';

class AiAgentsAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }
}

export default new AiAgentsAPI();
