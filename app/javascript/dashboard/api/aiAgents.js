/* global axios */
import ApiClient from './ApiClient';

class AiAgentsAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  train(id) {
    return axios.post(`${this.url}/${id}/train`);
  }

  playground(id, messages) {
    return axios.post(`${this.url}/${id}/playground`, { messages });
  }
}

export default new AiAgentsAPI();
