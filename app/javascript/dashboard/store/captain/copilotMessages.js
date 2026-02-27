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
      const threadId = data.copilot_thread?.id;
      if (!threadId) return;

      // Reset stale streaming state as persisted messages arrive.
      if (data.message_type === 'user') {
        commit('CLEAR_STREAMING', threadId);
        commit('CLEAR_STREAMING_THINKING', threadId);
        commit('CLEAR_STREAMING_TRANSLATION', threadId);
      }

      if (data.message_type === 'assistant') {
        commit('CLEAR_STREAMING', threadId);
        commit('CLEAR_STREAMING_THINKING', threadId);
        commit('CLEAR_STREAMING_TRANSLATION', threadId);
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
    // Map of threadId → { thinking: string } for in-progress reasoning stream
    streamingThinking: {},
    // Map of threadId → { translation: string } for in-progress translation streaming
    streamingTranslation: {},
  },
  getters: {
    ...baseStore.getters,
    getStreamingContent: state => threadId => {
      return state.streamingContent[threadId] || null;
    },
    getStreamingThinking: state => threadId => {
      return state.streamingThinking[threadId] || null;
    },
    getStreamingTranslation: state => threadId => {
      return state.streamingTranslation[threadId] || null;
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
    SET_STREAMING_THINKING(state, { threadId, thinking }) {
      state.streamingThinking = {
        ...state.streamingThinking,
        [threadId]: thinking,
      };
    },
    CLEAR_STREAMING_THINKING(state, threadId) {
      const { [threadId]: _, ...rest } = state.streamingThinking;
      state.streamingThinking = rest;
    },
    SET_STREAMING_TRANSLATION(state, { threadId, translation }) {
      state.streamingTranslation = {
        ...state.streamingTranslation,
        [threadId]: translation,
      };
    },
    CLEAR_STREAMING_TRANSLATION(state, threadId) {
      const { [threadId]: _, ...rest } = state.streamingTranslation;
      state.streamingTranslation = rest;
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
    setStreamingThinking({ commit }, { threadId, thinking }) {
      commit('SET_STREAMING_THINKING', { threadId, thinking });
    },
    clearStreamingThinking({ commit }, threadId) {
      commit('CLEAR_STREAMING_THINKING', threadId);
    },
    setStreamingTranslation({ commit }, { threadId, translation }) {
      commit('SET_STREAMING_TRANSLATION', { threadId, translation });
    },
    clearStreamingTranslation({ commit }, threadId) {
      commit('CLEAR_STREAMING_TRANSLATION', threadId);
    },
  },
};
