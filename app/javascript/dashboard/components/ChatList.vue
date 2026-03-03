<script setup>
// [TODO] This componet is too big and bulky to be in the same file, we can consider splitting this into multiple
// composables and components, useVirtualChatList, useChatlistFilters
import {
  ref,
  unref,
  provide,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  defineEmits,
} from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import ConversationItem from './ConversationItem.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useChatListKeyboardEvents } from 'dashboard/composables/chatlist/useChatListKeyboardEvents';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useEventListener } from '@vueuse/core';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { conversationListPageURL } from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';
import ConversationApi from 'dashboard/api/inbox/conversation';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings, updateUISettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

const conversationListRef = ref(null);
const conversationDynamicScroller = ref(null);

// --- Resizable sidebar width ---
const CHATLIST_MIN_WIDTH = 280;
const CHATLIST_MAX_WIDTH = 560;
const CHATLIST_DEFAULT_WIDTH = 340;

const chatListWidth = ref(
  uiSettings.value.chatlist_custom_width || CHATLIST_DEFAULT_WIDTH
);
const isResizing = ref(false);

const onResizeMove = event => {
  if (!isResizing.value) return;
  const container = document.querySelector('.conversations-list-wrap');
  if (!container) return;
  const rect = container.getBoundingClientRect();
  const newWidth = event.clientX - rect.left;
  chatListWidth.value = Math.min(
    CHATLIST_MAX_WIDTH,
    Math.max(CHATLIST_MIN_WIDTH, newWidth)
  );
};

const onResizeEnd = () => {
  if (!isResizing.value) return;
  isResizing.value = false;
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  document.removeEventListener('mousemove', onResizeMove);
  document.removeEventListener('mouseup', onResizeEnd);
  updateUISettings({ chatlist_custom_width: chatListWidth.value });
};

const onResizeStart = () => {
  isResizing.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  document.addEventListener('mousemove', onResizeMove);
  document.addEventListener('mouseup', onResizeEnd);
};

onBeforeUnmount(() => {
  document.removeEventListener('mousemove', onResizeMove);
  document.removeEventListener('mouseup', onResizeEnd);
});

provide('contextMenuElementTarget', conversationDynamicScroller);

const activeAssigneeTab = ref(wootConstants.ASSIGNEE_TYPE.ME);
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
let pinnedUnreadIds = new Set();
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const isContextMenuOpen = ref(false);
const appliedFilter = ref([]);
const emptyTabRecoveryKey = ref(null);
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unresolvedChatsList = useMapGetter('getUnresolvedChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');

useChatListKeyboardEvents(conversationListRef);
const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onAssignTeamsForBulk,
  onUpdateConversations,
} = useBulkActions();

// --- Batch edit mode ---
const isBatchEditMode = ref(false);

function toggleBatchEditMode() {
  isBatchEditMode.value = !isBatchEditMode.value;
  if (!isBatchEditMode.value) {
    resetBulkActions();
  }
}

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

const assigneeTabItems = computed(() => {
  return filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key, count: countKey }) => ({
    key,
    name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
    count: conversationStats.value[countKey] || 0,
  }));
});

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNRESOLVED ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNREAD
  );
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : activeAssigneeTab.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  const tab = assigneeTabItems.value.find(
    item => item.key === activeAssigneeTab.value
  );
  return tab ? tab.count : 0;
});

const conversationsPerPage = computed(() => {
  return uiSettings.value.conversations_per_page || 25;
});

const conversationListPagination = computed(() => {
  const perPage = conversationsPerPage.value;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < perPage &&
    activeAssigneeTabCount.value < perPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  const safeCurrentPage = Number(currentPage.value);
  return (Number.isFinite(safeCurrentPage) ? safeCurrentPage : 0) + 1;
});

const conversationFilters = computed(() => {
  const filters = {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType: activeAssigneeTab.value,
    status: activeStatus.value,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: props.label ? [props.label] : undefined,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    perPage: conversationsPerPage.value,
  };

  if (
    activeAssigneeTab.value === 'unresolved' ||
    activeAssigneeTab.value === 'unread'
  ) {
    filters.status = 'all';
  }

  return filters;
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    if (props.label === '__no_label__') {
      return t('SIDEBAR.NO_LABEL');
    }
    return `#${props.label}`;
  }
  if (props.conversationType === 'mention') {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (props.conversationType === 'participating') {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === 'unattended') {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

const conversationList = computed(() => {
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    if (activeAssigneeTab.value === 'me') {
      localConversationList = [...mineChatsList.value(filters)];
    } else if (activeAssigneeTab.value === 'unread') {
      const allConvs = allChatList.value(filters);
      allConvs.forEach(c => {
        if (c.unread_count > 0) pinnedUnreadIds.add(c.id);
      });
      localConversationList = allConvs.filter(
        c => c.unread_count > 0 || pinnedUnreadIds.has(c.id)
      );
    } else if (activeAssigneeTab.value === 'unresolved') {
      localConversationList = [...unresolvedChatsList.value(filters)];
    } else {
      localConversationList = [...allChatList.value(filters)];
    }
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  const safeCurrentPage = Number(currentPage.value);
  const loadedPages = Number.isFinite(safeCurrentPage) ? safeCurrentPage : 0;
  const effectivePages = Math.max(1, loadedPages);
  const visibleItemsLimit = effectivePages * conversationsPerPage.value;
  return localConversationList.slice(0, visibleItemsLimit);
});

function resetConversationListScroll() {
  if (conversationDynamicScroller.value) {
    conversationDynamicScroller.value.scrollTop = 0;
  }
}

function debugChatList(message, data = {}) {
  if (
    typeof window !== 'undefined' &&
    window.localStorage?.getItem('cw_debug_chat_list') === '1'
  ) {
    // eslint-disable-next-line no-console
    console.debug(`[ChatList] ${message}`, data);
  }
}

function emitConversationLoaded() {
  emit('conversationLoad');
  // [VITE] removing this since the library has changed
  // nextTick(() => {
  //   // Addressing a known issue in the virtual list library where dynamically added items
  //   // might not render correctly. This workaround involves a slight manual adjustment
  //   // to the scroll position, triggering the list to refresh its rendering.
  //   const virtualList = conversationListRef.value;
  //   const scrollToOffset = virtualList?.scrollToOffset;
  //   const currentOffset = virtualList?.getOffset() || 0;
  //   if (scrollToOffset) {
  //     scrollToOffset(currentOffset + 1);
  //   }
  // });
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  const safeCurrentPage = Number(currentFiltersPage.value);
  const page = (Number.isFinite(safeCurrentPage) ? safeCurrentPage : 0) + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  const safeCurrentPage = Number(currentFiltersPage.value);
  const page = (Number.isFinite(safeCurrentPage) ? safeCurrentPage : 0) + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  pinnedUnreadIds = new Set();
  resetConversationListScroll();
  appliedFilter.value = [];
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('clearConversationFilters');
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
}

function loadMoreConversations() {
  debugChatList('loadMoreConversations:called', {
    hasCurrentPageEndReached: hasCurrentPageEndReached.value,
    chatListLoading: chatListLoading.value,
    currentPage: currentPage.value,
    activeAssigneeTab: activeAssigneeTab.value,
  });
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    debugChatList('loadMoreConversations:skipped');
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

function handleScroll() {
  const el = conversationDynamicScroller.value;
  if (!el) return;

  const { scrollTop, scrollHeight, clientHeight } = el;
  const isNearBottom = scrollHeight - (scrollTop + clientHeight) < 100;
  debugChatList('handleScroll', {
    scrollTop,
    scrollHeight,
    clientHeight,
    isNearBottom,
  });
  if (isNearBottom) {
    loadMoreConversations();
  }
}

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value !== selectedTab) {
    resetBulkActions();
    emitter.emit('clearSearchInput');
    activeAssigneeTab.value = selectedTab;
    return;
  }

  // If the same tab is reselected, force a refresh to avoid stale/empty states.
  pinnedUnreadIds = new Set();
  resetConversationListScroll();
  store.dispatch('conversationPage/reset');
  fetchConversations();
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
  } else {
    activeSortBy.value = value;
  }
  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = 'mention';
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = 'unattended';
  }
  router.push(
    conversationListPageURL({
      accountId,
      conversationType: conversationType,
      customViewId: props.foldersId,
      inboxId,
      label,
      teamId,
    })
  );
}

const markAllLabelReadDialogRef = ref(null);
const resolveAllLabelDialogRef = ref(null);

function onMarkAllLabelRead() {
  markAllLabelReadDialogRef.value.open();
}

function onResolveAllLabel() {
  resolveAllLabelDialogRef.value.open();
}

async function confirmMarkAllLabelRead() {
  try {
    await ConversationApi.bulkReadByLabel({ label: props.label });
    useAlert(t('CHAT_LIST.HEADER.ACTIONS.MARK_ALL_READ_SUCCESS'));
    markAllLabelReadDialogRef.value.close();
    store.dispatch('emptyAllConversations');
    resetAndFetchData();
  } catch (error) {
    useAlert(t('CHAT_LIST.HEADER.ACTIONS.OPERATION_FAILED'));
  }
}

async function confirmResolveAllLabel() {
  try {
    await ConversationApi.bulkResolveByLabel({ label: props.label });
    useAlert(t('CHAT_LIST.HEADER.ACTIONS.MARK_ALL_RESOLVED_SUCCESS'));
    resolveAllLabelDialogRef.value.close();
    store.dispatch('emptyAllConversations');
    resetAndFetchData();
  } catch (error) {
    useAlert(t('CHAT_LIST.HEADER.ACTIONS.OPERATION_FAILED'));
  }
}

const displayLabel = computed(() => {
  if (!props.label) return '';
  if (props.label === '__no_label__') return t('SIDEBAR.NO_LABEL');
  return props.label;
});

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(conversationId, status, snoozedUntil) {
  store
    .dispatch('toggleStatus', {
      conversationId,
      status,
      snoozedUntil,
    })
    .then(() => {
      useAlert(t('CONVERSATION.CHANGE_STATUS'));
    });
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return store.getters.getConversationById(item)?.status === status;
  });
}

function onContextMenuToggle(state) {
  isContextMenuOpen.value = state;
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  store.dispatch('conversationStats/get', conversationFilters.value);
});

useEventListener(conversationDynamicScroller, 'scroll', handleScroll);

function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;
  activeStatus.value = status || wootConstants.STATUS_TYPE.OPEN;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
});

const showEndOfListMessage = computed(() => {
  return (
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

// Show a full-area loading spinner when fetching data for an unvisited tab/view.
// currentPage is 0 when the tab has never been loaded (no cache),
// preventing stale cross-tab data from appearing during the fetch.
const showConversationLoader = computed(() => {
  return chatListLoading.value && !currentPage.value;
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

// --- Batch operations for edit mode ---
const batchDeleteDialogRef = ref(null);

async function batchMarkRead() {
  const ids = selectedConversations.value;
  if (!ids.length) return;
  try {
    await store.dispatch('batchMarkRead', { ids });
    useAlert(t('CHAT_LIST.BATCH_EDIT.SUCCESS'));
    resetBulkActions();
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.FAILED'));
  }
}

async function batchMarkUnread() {
  const ids = selectedConversations.value;
  if (!ids.length) return;
  try {
    await store.dispatch('batchMarkUnread', { ids });
    useAlert(t('CHAT_LIST.BATCH_EDIT.SUCCESS'));
    resetBulkActions();
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.FAILED'));
  }
}

async function batchMarkResolved() {
  const ids = selectedConversations.value;
  if (!ids.length) return;
  ids.forEach(id => {
    store.commit('CHANGE_CONVERSATION_STATUS', {
      conversationId: id,
      status: 'resolved',
      snoozedUntil: null,
    });
  });
  try {
    await store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids,
      fields: { status: 'resolved' },
    });
    useAlert(t('CHAT_LIST.BATCH_EDIT.SUCCESS'));
    resetBulkActions();
    store.dispatch('conversationStats/get', conversationFilters.value);
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.FAILED'));
  }
}

async function batchMarkUnresolved() {
  const ids = selectedConversations.value;
  if (!ids.length) return;
  ids.forEach(id => {
    store.commit('CHANGE_CONVERSATION_STATUS', {
      conversationId: id,
      status: 'open',
      snoozedUntil: null,
    });
  });
  try {
    await store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids,
      fields: { status: 'open' },
    });
    useAlert(t('CHAT_LIST.BATCH_EDIT.SUCCESS'));
    resetBulkActions();
    store.dispatch('conversationStats/get', conversationFilters.value);
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.FAILED'));
  }
}

async function batchRemovePriority() {
  const ids = selectedConversations.value;
  if (!ids.length) return;
  ids.forEach(id => {
    store.commit('ASSIGN_PRIORITY', { conversationId: id, priority: null });
  });
  try {
    await store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids,
      fields: { priority: null },
    });
    useAlert(t('CHAT_LIST.BATCH_EDIT.SUCCESS'));
    resetBulkActions();
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.FAILED'));
  }
}

function batchDeleteInit() {
  if (!selectedConversations.value.length) return;
  batchDeleteDialogRef.value.open();
}

async function batchDeleteConversations() {
  const ids = [...selectedConversations.value];
  try {
    await Promise.all(ids.map(id => store.dispatch('deleteConversation', id)));
    useAlert(t('CHAT_LIST.BATCH_EDIT.DELETE_SUCCESS'));
    resetBulkActions();
    batchDeleteDialogRef.value.close();
    redirectToConversationList();
  } catch {
    useAlert(t('CHAT_LIST.BATCH_EDIT.DELETE_FAILED'));
  }
}

async function removeAllLabels(conversationId) {
  try {
    await store.dispatch('conversationLabels/update', {
      conversationId,
      labels: [],
    });
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.REMOVE_ALL_LABELS_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.REMOVE_ALL_LABELS_FAILED'));
  }
}

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeAllLabels', removeAllLabels);
provide('updateConversationStatus', toggleConversationStatus);
provide('toggleContextMenu', onContextMenuToggle);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);
provide('isBatchEditMode', isBatchEditMode);

watch(activeTeam, () => resetAndFetchData());

watch(activeAssigneeTab, (newTab, oldTab) => {
  if (oldTab === 'unread' && newTab !== 'unread') {
    pinnedUnreadIds = new Set();
  }
  resetConversationListScroll();
  if (!currentPage.value) {
    fetchConversations();
  }
});

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);
watch(
  computed(() => props.label),
  () => {
    if (
      props.label &&
      route.query.assignee_type === wootConstants.ASSIGNEE_TYPE.UNREAD
    ) {
      activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.UNREAD;
    }
    resetAndFetchData();
  }
);
watch(
  computed(() => props.conversationType),
  () => resetAndFetchData()
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('updateChatListFilters', newVal);
  }
});

// Re-fetch when per-page setting changes (e.g. user updates it from settings page)
watch(conversationsPerPage, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    resetAndFetchData();
  }
});

// When a tab's visible list is empty (never loaded, or emptied by a bulk action),
// reset its pagination and fetch page 1.
// Uses a recoveryKey to avoid firing more than once per tab+filter combo.
watch(
  [activeAssigneeTab, currentPage, chatListLoading, conversationList],
  () => {
    if (hasAppliedFiltersOrActiveFolders.value) return;
    if (conversationList.value.length) {
      emptyTabRecoveryKey.value = null;
      return;
    }

    if (chatListLoading.value || hasCurrentPageEndReached.value) return;

    const recoveryKey = `${activeAssigneeTab.value}:${props.label || ''}:${
      props.conversationInbox || ''
    }:${props.teamId || ''}`;

    if (emptyTabRecoveryKey.value !== recoveryKey) {
      emptyTabRecoveryKey.value = recoveryKey;
      if (currentPage.value > 0) {
        store.dispatch('conversationPage/setCurrentPage', {
          filter: currentPageFilterKey.value,
          page: 0,
        });
      }
      fetchConversations();
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 bg-n-solid-1 conversations-list-wrap relative"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : '',
    ]"
    :style="isOnExpandedLayout ? {} : { width: `${chatListWidth}px` }"
  >
    <slot />
    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      :is-batch-edit-mode="isBatchEditMode"
      :label="label"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
      @mark-all-label-read="onMarkAllLabelRead"
      @resolve-all-label="onResolveAllLabel"
      @toggle-batch-edit="toggleBatchEditMode"
    />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <ChatTypeTabs
      v-if="!hasAppliedFiltersOrActiveFolders"
      :items="assigneeTabItems"
      :active-tab="activeAssigneeTab"
      is-compact
      @chat-tab-change="updateAssigneeTab"
    />

    <p
      v-if="
        !chatListLoading && !conversationList.length && !showConversationLoader
      "
      class="flex items-center justify-center p-4 overflow-auto"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>
    <div
      v-if="showConversationLoader"
      class="flex items-center justify-center flex-1 p-4"
    >
      <Spinner class="text-n-brand" />
    </div>
    <ConversationBulkActions
      v-if="selectedConversations.length"
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      @select-all-conversations="toggleSelectAll"
      @assign-agent="onAssignAgent"
      @update-conversations="onUpdateConversations"
      @assign-labels="onAssignLabels"
      @assign-team="onAssignTeamsForBulk"
      @batch-mark-read="batchMarkRead"
      @batch-mark-unread="batchMarkUnread"
      @batch-mark-resolved="batchMarkResolved"
      @batch-mark-unresolved="batchMarkUnresolved"
      @batch-remove-priority="batchRemovePriority"
      @batch-delete="batchDeleteInit"
    />
    <div
      v-show="!showConversationLoader"
      ref="conversationListRef"
      class="flex-1 overflow-hidden conversations-list hover:overflow-y-auto"
      :class="{ 'overflow-hidden': isContextMenuOpen }"
    >
      <div
        ref="conversationDynamicScroller"
        class="w-full h-full overflow-auto"
      >
        <ConversationItem
          v-for="item in conversationList"
          :key="item.id"
          :source="item"
          :label="label"
          :team-id="teamId"
          :folders-id="foldersId"
          :conversation-type="conversationType"
          :show-assignee="showAssigneeInConversationCard"
          @select-conversation="selectConversation"
          @de-select-conversation="deSelectConversation"
        />
        <div v-if="chatListLoading" class="flex justify-center my-4">
          <Spinner class="text-n-brand" />
        </div>
        <p
          v-else-if="showEndOfListMessage"
          class="p-4 text-center text-n-slate-11"
        >
          {{ $t('CHAT_LIST.EOF') }}
        </p>
        <div v-else class="h-2 w-full" />
      </div>
    </div>
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <Dialog
      ref="batchDeleteDialogRef"
      type="alert"
      :title="
        $t('CHAT_LIST.BATCH_EDIT.DELETE_CONFIRM_TITLE', {
          count: selectedConversations.length,
        })
      "
      :description="
        $t('CHAT_LIST.BATCH_EDIT.DELETE_CONFIRM_DESC', {
          count: selectedConversations.length,
        })
      "
      :confirm-button-label="$t('CHAT_LIST.BATCH_EDIT.DELETE_CONFIRM_BUTTON')"
      @confirm="batchDeleteConversations"
    />
    <Dialog
      ref="markAllLabelReadDialogRef"
      type="alert"
      :title="$t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_MARK_ALL_READ_TITLE')"
      :description="
        $t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_MARK_ALL_READ_DESC', {
          label: displayLabel,
        })
      "
      :confirm-button-label="$t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_BUTTON')"
      @confirm="confirmMarkAllLabelRead"
    />
    <Dialog
      ref="resolveAllLabelDialogRef"
      type="alert"
      :title="$t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_MARK_ALL_RESOLVED_TITLE')"
      :description="
        $t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_MARK_ALL_RESOLVED_DESC', {
          label: displayLabel,
        })
      "
      :confirm-button-label="$t('CHAT_LIST.HEADER.ACTIONS.CONFIRM_BUTTON')"
      @confirm="confirmResolveAllLabel"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <!-- Resize handle (right edge) -->
    <div
      v-if="!isOnExpandedLayout"
      class="absolute top-0 bottom-0 w-1 cursor-col-resize z-10 ltr:right-0 rtl:left-0 group hover:bg-n-iris-6 transition-colors"
      :class="isResizing ? 'bg-n-iris-6' : 'bg-transparent'"
      @mousedown.prevent="onResizeStart"
      @dblclick.prevent="
        () => {
          chatListWidth = CHATLIST_DEFAULT_WIDTH;
          updateUISettings({ chatlist_custom_width: CHATLIST_DEFAULT_WIDTH });
        }
      "
    >
      <div
        class="absolute top-1/2 -translate-y-1/2 ltr:-left-0.5 rtl:-right-0.5 w-1 h-8 rounded-full bg-n-slate-8 opacity-0 group-hover:opacity-100 transition-opacity"
        :class="{ 'opacity-100': isResizing }"
      />
    </div>
  </div>
</template>
