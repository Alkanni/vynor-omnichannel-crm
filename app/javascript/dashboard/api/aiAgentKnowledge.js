/* global axios */
import ApiClient from './ApiClient';

class AiAgentKnowledgeAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  sourcesUrl(agentId) {
    return `${this.url}/${agentId}/knowledge_sources`;
  }

  productsUrl(agentId) {
    return `${this.url}/${agentId}/products`;
  }

  getSources(agentId, sourceType) {
    return axios.get(this.sourcesUrl(agentId), {
      params: { source_type: sourceType },
    });
  }

  createSource(agentId, data) {
    return axios.post(this.sourcesUrl(agentId), data);
  }

  updateSource(agentId, id, data) {
    return axios.patch(`${this.sourcesUrl(agentId)}/${id}`, data);
  }

  deleteSource(agentId, id) {
    return axios.delete(`${this.sourcesUrl(agentId)}/${id}`);
  }

  getStats(agentId) {
    return axios.get(`${this.sourcesUrl(agentId)}/stats`);
  }

  collectLinks(agentId, url) {
    return axios.post(`${this.sourcesUrl(agentId)}/collect_links`, { url });
  }

  addWebsites(agentId, urls) {
    return axios.post(`${this.sourcesUrl(agentId)}/websites`, { urls });
  }

  resyncSource(agentId, id) {
    return axios.post(`${this.sourcesUrl(agentId)}/${id}/resync`);
  }

  getSourceChunks(agentId, id, { signal } = {}) {
    return axios.get(`${this.sourcesUrl(agentId)}/${id}/chunks`, { signal });
  }

  testRetrieval(agentId, query, history, { signal } = {}) {
    return axios.post(
      `${this.url}/${agentId}/retrieval_test`,
      { query, history },
      { signal }
    );
  }

  bulkDeleteSources(agentId, ids) {
    return axios.post(`${this.sourcesUrl(agentId)}/bulk_destroy`, { ids });
  }

  uploadFile(agentId, file, onUploadProgress) {
    const formData = new FormData();
    formData.append('source_type', 'file');
    formData.append('file', file);
    return axios.post(this.sourcesUrl(agentId), formData, { onUploadProgress });
  }

  getProducts(agentId, query) {
    return axios.get(this.productsUrl(agentId), { params: { q: query } });
  }

  createProduct(agentId, formData) {
    return axios.post(this.productsUrl(agentId), formData);
  }

  updateProduct(agentId, id, formData) {
    return axios.patch(`${this.productsUrl(agentId)}/${id}`, formData);
  }

  deleteProduct(agentId, id) {
    return axios.delete(`${this.productsUrl(agentId)}/${id}`);
  }

  bulkDeleteProducts(agentId, ids) {
    return axios.post(`${this.productsUrl(agentId)}/bulk_destroy`, { ids });
  }
}

export default new AiAgentKnowledgeAPI();
