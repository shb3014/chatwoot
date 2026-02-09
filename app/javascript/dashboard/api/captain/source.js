/* global axios */
import ApiClient from '../ApiClient';

class CaptainSource extends ApiClient {
  constructor() {
    super('captain/sources', { accountScoped: true });
  }

  get({ page = 1, sourceType, search } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        source_type: sourceType,
        search,
      },
    });
  }

  recrawl(id) {
    return axios.post(`${this.url}/${id}/recrawl`);
  }
}

export default new CaptainSource();
