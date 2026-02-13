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
}

export default new CaptainTranslation();
