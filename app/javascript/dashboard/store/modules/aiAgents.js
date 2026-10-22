import AiAgentsAPI from 'dashboard/api/aiAgents';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { createStore } from '../storeFactory';

export default createStore({
  name: 'AiAgent',
  API: AiAgentsAPI,
  actions: mutationTypes => ({
    async duplicate({ commit }, id) {
      commit(mutationTypes.SET_UI_FLAG, { creatingItem: true });
      try {
        const response = await AiAgentsAPI.duplicate(id);
        commit(mutationTypes.UPSERT, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutationTypes.SET_UI_FLAG, { creatingItem: false });
      }
    },
  }),
});
