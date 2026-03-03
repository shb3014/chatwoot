import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';

const recentlyMarkedRead = new Set();

export default {
  markMessagesRead: async ({ commit, state }, data) => {
    const chat = state.allConversations.find(c => c.id === data.id);
    if (chat && chat.unread_count > 0) {
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id: data.id,
        lastSeen: Date.now() / 1000,
      });
      if (!recentlyMarkedRead.has(data.id)) {
        recentlyMarkedRead.add(data.id);
        commit('conversationStats/decrementUnreadCount', 1, { root: true });
        if (chat.labels?.length) {
          const labelsMap = {};
          chat.labels.forEach(l => {
            labelsMap[l] = 1;
          });
          commit('labels/decrementLabelUnreadCounts', labelsMap, {
            root: true,
          });
        }
      }
    }
    try {
      await ConversationApi.markMessageRead(data);
    } catch (error) {
      // Handle error
    } finally {
      setTimeout(() => recentlyMarkedRead.delete(data.id), 5000);
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

  batchMarkRead: async ({ commit, state }, { ids }) => {
    let unreadDecrement = 0;
    const labelDecrements = {};
    ids.forEach(id => {
      const chat = state.allConversations.find(c => c.id === id);
      if (chat && chat.unread_count > 0) {
        unreadDecrement += 1;
        (chat.labels || []).forEach(label => {
          labelDecrements[label] = (labelDecrements[label] || 0) + 1;
        });
      }
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen: Date.now() / 1000,
      });
    });
    if (unreadDecrement > 0) {
      commit('conversationStats/decrementUnreadCount', unreadDecrement, {
        root: true,
      });
      if (Object.keys(labelDecrements).length) {
        commit('labels/decrementLabelUnreadCounts', labelDecrements, {
          root: true,
        });
      }
    }
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
