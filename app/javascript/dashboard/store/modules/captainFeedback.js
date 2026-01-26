import CaptainAPI from '../../api/captain';
import * as types from '../mutation-types';

const state = {
  feedbacks: {},
  uiFlags: {
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getFeedbackForMessage: $state => messageId => {
    return $state.feedbacks[messageId];
  },
  isCreating: $state => $state.uiFlags.isCreating,
  isUpdating: $state => $state.uiFlags.isUpdating,
};

export const actions = {
  create: async ({ commit }, { messageId, rating, feedbackType, notes }) => {
    commit(types.default.SET_CAPTAIN_FEEDBACK_UI_FLAG, { isCreating: true });

    try {
      const response = await CaptainAPI.createMessageFeedback({
        message_id: messageId,
        rating,
        feedback_type: feedbackType,
        notes,
      });

      commit(types.default.SET_CAPTAIN_FEEDBACK, {
        messageId,
        feedback: response.data.feedback,
      });

      return response.data;
    } finally {
      commit(types.default.SET_CAPTAIN_FEEDBACK_UI_FLAG, { isCreating: false });
    }
  },

  update: async (
    { commit },
    { messageId, feedbackId, issueResolved, resolutionMethod }
  ) => {
    commit(types.default.SET_CAPTAIN_FEEDBACK_UI_FLAG, { isUpdating: true });

    try {
      const response = await CaptainAPI.updateMessageFeedback(feedbackId, {
        issue_resolved: issueResolved,
        resolution_method: resolutionMethod,
      });

      commit(types.default.SET_CAPTAIN_FEEDBACK, {
        messageId,
        feedback: response.data.feedback,
      });

      return response.data;
    } finally {
      commit(types.default.SET_CAPTAIN_FEEDBACK_UI_FLAG, { isUpdating: false });
    }
  },
};

export const mutations = {
  [types.default.SET_CAPTAIN_FEEDBACK]($state, { messageId, feedback }) {
    $state.feedbacks = {
      ...$state.feedbacks,
      [messageId]: feedback,
    };
  },

  [types.default.SET_CAPTAIN_FEEDBACK_UI_FLAG]($state, flags) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...flags,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
