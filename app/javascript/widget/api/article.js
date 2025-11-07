import endPoints from 'widget/api/endPoints';
import { API } from 'widget/helpers/axios';

export const getMostReadArticles = async (slug, locale) => {
  const urlData = endPoints.getMostReadArticles(slug, locale);
  return API.get(urlData.url, { params: urlData.params });
};

export const searchArticles = async (slug, locale, query) => {
  const urlData = endPoints.searchArticles(slug, locale, query);
  return API.get(urlData.url, { params: urlData.params });
};
