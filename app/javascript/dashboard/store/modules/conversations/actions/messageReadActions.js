import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';

export default {
  markMessagesRead: async ({ commit }, data) => {
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen },
      } = await ConversationApi.markMessageRead(data);
      setTimeout(
        () =>
          commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, { id, lastSeen }),
        4000
      );
    } catch (error) {
      // Handle error
    }
  },

  markMessagesUnread: async ({ commit }, { id }) => {
    try {
      const {
        data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
      } = await ConversationApi.markMessagesUnread({ id });
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen,
        unreadCount,
      });
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  batchMarkRead: async ({ commit }, { ids }) => {
    ids.forEach(id =>
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen: Date.now() / 1000,
      })
    );
    try {
      await ConversationApi.batchMarkRead({ ids });
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  batchMarkUnread: async ({ commit, state }, { ids }) => {
    ids.forEach(id => {
      const chat = state.allConversations.find(c => c.id === id);
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen: chat?.agent_last_seen_at,
        unreadCount: Math.max(chat?.unread_count || 0, 1),
      });
    });
    try {
      await ConversationApi.batchMarkUnread({ ids });
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};
