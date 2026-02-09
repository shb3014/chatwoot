import CaptainSourceAPI from 'dashboard/api/captain/source';
import { createStore } from './storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainSource',
  API: CaptainSourceAPI,
  actions: mutations => ({
    recrawl: async ({ commit }, id) => {
      try {
        const response = await CaptainSourceAPI.recrawl(id);
        commit(mutations.EDIT, response.data);
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      }
    },
  }),
});
