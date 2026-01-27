/* global axios */
import ApiClient from '../ApiClient';

class CaptainLearnedConversations extends ApiClient {
  constructor() {
    super('captain/learned_conversations', { accountScoped: true });
  }

  get({ page = 1, search, assistantId, status } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        search,
        assistant_id: assistantId,
        status,
      },
    });
  }

  learn({ conversationId, force = false }) {
    return axios.post(this.url, {
      conversation_id: conversationId,
      force,
    });
  }

  forget(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new CaptainLearnedConversations();
