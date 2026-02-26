/* global axios */
import ApiClient from '../ApiClient';

class CaptainTranslation extends ApiClient {
  constructor() {
    super('captain/translation', { accountScoped: true });
  }

  translate({ content, targetLanguage }) {
    return axios.post(this.url, {
      content,
      target_language: targetLanguage,
    });
  }

  /**
   * Batch-translate messages in a single streaming LLM call.
   * Results arrive via ActionCable, not in the HTTP response.
   * @param {Object} params
   * @param {number} params.conversationId
   * @param {Array<{id: number, content: string}>} params.messages
   * @param {string} params.targetLanguage
   */
  translateBatch({ conversationId, messages, targetLanguage }) {
    return axios.post(`${this.url}/batch`, {
      conversation_id: conversationId,
      messages,
      target_language: targetLanguage,
    });
  }
}

export default new CaptainTranslation();
