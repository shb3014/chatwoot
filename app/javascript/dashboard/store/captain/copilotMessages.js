import CopilotMessagesAPI from 'dashboard/api/captain/copilotMessages';
import { createStore } from './storeFactory';

const baseStore = createStore({
  name: 'CopilotMessages',
  API: CopilotMessagesAPI,
  getters: {
    getMessagesByThreadId: state => copilotThreadId => {
      return state.records
        .filter(record => record.copilot_thread?.id === Number(copilotThreadId))
        .sort((a, b) => a.id - b.id);
    },
  },
  actions: mutationTypes => ({
    upsert({ commit }, data) {
      commit(mutationTypes.UPSERT, data);
      // Clear streaming content when a real message arrives
      if (data.copilot_thread?.id) {
        commit('CLEAR_STREAMING', data.copilot_thread.id);
      }
    },
  }),
});

// Extend the base store with streaming support
const originalState = baseStore.state;

export default {
  ...baseStore,
  state: {
    ...originalState,
    // Map of threadId → { content: string } for in-progress streaming
    streamingContent: {},
  },
  getters: {
    ...baseStore.getters,
    getStreamingContent: state => threadId => {
      return state.streamingContent[threadId] || null;
    },
  },
  mutations: {
    ...baseStore.mutations,
    SET_STREAMING(state, { threadId, content }) {
      state.streamingContent = {
        ...state.streamingContent,
        [threadId]: content,
      };
    },
    CLEAR_STREAMING(state, threadId) {
      const { [threadId]: _, ...rest } = state.streamingContent;
      state.streamingContent = rest;
    },
  },
  actions: {
    ...baseStore.actions,
    setStreamingContent({ commit }, { threadId, content }) {
      commit('SET_STREAMING', { threadId, content });
    },
    clearStreamingContent({ commit }, threadId) {
      commit('CLEAR_STREAMING', threadId);
    },
  },
};
