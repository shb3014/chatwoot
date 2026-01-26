/* global axios */

import ApiClient from './ApiClient';

class CaptainAPI extends ApiClient {
  constructor() {
    super('captain', { accountScoped: true });
  }

  createMessageFeedback({ message_id, rating, feedback_type, notes }) {
    return axios.post(`${this.url}/message_feedbacks`, {
      message_id,
      rating,
      feedback_type,
      notes,
    });
  }

  updateMessageFeedback(messageId, { issue_resolved, resolution_method }) {
    return axios.put(`${this.url}/message_feedbacks/${messageId}`, {
      issue_resolved,
      resolution_method,
    });
  }
}

export default new CaptainAPI();
