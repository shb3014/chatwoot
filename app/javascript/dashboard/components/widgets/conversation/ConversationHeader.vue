<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import types from 'dashboard/store/mutation-types';
import { OnClickOutside } from '@vueuse/components';
import CaptainLearnedConversationsAPI from 'dashboard/api/captain/learnedConversations';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const isLearningMenuOpen = ref(false);
const isLearningAction = ref(false);
const learningState = computed(
  () => currentChat.value?.captain_learning || null
);
const learningStatus = computed(() => learningState.value?.status || null);
const learningId = computed(() => learningState.value?.id || null);
const learningRating = computed(
  () => learningState.value?.quality_rating || null
);
const learningEligible = computed(
  () => currentChat.value?.captain_learning_eligible || false
);
const isLearned = computed(() => learningStatus.value === 'learned');

const learningMenuItems = computed(() => [
  {
    label: t('CAPTAIN_STATE_PANEL.LEARNING_MENU.RELEARN'),
    action: 'relearn',
    value: 'relearn',
  },
  {
    label: t('CAPTAIN_STATE_PANEL.LEARNING_MENU.FORGET'),
    action: 'delete',
    value: 'forget',
  },
]);

const applyLearningUpdate = learning => {
  if (!currentChat.value?.id) return;
  const updatedConversation = {
    ...currentChat.value,
    captain_learning: learning,
    captain_learning_eligible: true,
    updated_at: Date.now() / 1000,
  };
  store.commit(types.UPDATE_CONVERSATION, updatedConversation);
};

const learnConversation = async (force = false) => {
  if (!currentChat.value?.id) return;

  isLearningAction.value = true;
  try {
    const response = await CaptainLearnedConversationsAPI.learn({
      conversationId: currentChat.value.id,
      force,
    });
    const learning = response?.data?.payload;
    if (learning) {
      applyLearningUpdate(learning);
    }
    if (learning?.status === 'rejected') {
      useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.REJECTED'));
    } else {
      useAlert(
        force
          ? t('CAPTAIN_STATE_PANEL.LEARNING.RELEARN_SUCCESS')
          : t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_SUCCESS')
      );
    }
  } catch (error) {
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_ERROR'));
  } finally {
    isLearningAction.value = false;
  }
};

const forgetConversation = async () => {
  if (!learningId.value) return;

  isLearningAction.value = true;
  try {
    await CaptainLearnedConversationsAPI.forget(learningId.value);
    applyLearningUpdate(null);
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.FORGET_SUCCESS'));
  } catch (error) {
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.FORGET_ERROR'));
  } finally {
    isLearningAction.value = false;
    isLearningMenuOpen.value = false;
  }
};

const handleLearningAction = async ({ action }) => {
  if (action === 'relearn') {
    await learnConversation(true);
    return;
  }

  if (action === 'delete') {
    await forgetConversation();
  }
};

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 py-2 border-b bg-n-background border-n-weak h-24 xl:h-12"
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-2 rtl:ml-2"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        hide-offline-status
        rounded-full
      />
      <div
        class="flex flex-col items-start min-w-0 ml-2 overflow-hidden rtl:ml-0 rtl:mr-2"
      >
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-sm font-medium truncate leading-tight text-n-slate-12"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>

        <div
          class="flex items-center gap-2 overflow-hidden text-xs conversation--header--actions text-ellipsis whitespace-nowrap"
        >
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span v-if="isSnoozed" class="font-medium text-n-amber-10">
            {{ snoozedDisplayText }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <div v-if="learningEligible" class="flex items-center gap-2">
        <span
          v-if="isLearned"
          class="text-xs px-2 py-1 rounded bg-green-100 text-green-800 font-medium"
        >
          {{ $t('CAPTAIN_STATE_PANEL.LEARNING.LEARNED_LABEL') }}
        </span>
        <span
          v-if="isLearned && learningRating"
          class="text-xs px-2 py-1 rounded bg-n-alpha-2 text-n-slate-11 font-medium"
        >
          {{
            $t('CAPTAIN_STATE_PANEL.LEARNING.RATING', {
              rating: learningRating,
            })
          }}
        </span>
        <Button
          v-else
          size="xs"
          color="slate"
          :label="$t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_BUTTON')"
          :is-loading="isLearningAction"
          :disabled="isLearningAction"
          @click="learnConversation(true)"
        />
        <OnClickOutside @trigger="isLearningMenuOpen = false">
          <div v-if="isLearned" class="relative">
            <Button
              size="xs"
              color="slate"
              icon="i-lucide-chevron-down"
              @click="isLearningMenuOpen = !isLearningMenuOpen"
            />
            <DropdownMenu
              v-if="isLearningMenuOpen"
              class="mt-2 right-0"
              :menu-items="learningMenuItems"
              @action="handleLearningAction"
            />
          </div>
        </OnClickOutside>
      </div>
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
