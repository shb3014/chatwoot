import CaptainLearnedConversationsAPI from 'dashboard/api/captain/learnedConversations';
import { createStore } from './storeFactory';

export default createStore({
  name: 'captainLearnedConversation',
  API: CaptainLearnedConversationsAPI,
});
