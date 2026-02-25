<script>
import { getUnixTime } from 'date-fns';
import { findSnoozeTime } from 'dashboard/helper/snoozeHelpers';
import { emitter } from 'shared/helpers/mitt';
import wootConstants from 'dashboard/constants/globals';
import {
  CMD_BULK_ACTION_SNOOZE_CONVERSATION,
  CMD_BULK_ACTION_REOPEN_CONVERSATION,
  CMD_BULK_ACTION_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

import NextButton from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import AgentSelector from './AgentSelector.vue';
import LabelActions from './LabelActions.vue';
import TeamActions from './TeamActions.vue';
import CustomSnoozeModal from 'dashboard/components/CustomSnoozeModal.vue';
export default {
  components: {
    AgentSelector,
    LabelActions,
    TeamActions,
    CustomSnoozeModal,
    NextButton,
    DropdownMenu,
  },
  props: {
    conversations: {
      type: Array,
      default: () => [],
    },
    allConversationsSelected: {
      type: Boolean,
      default: false,
    },
    selectedInboxes: {
      type: Array,
      default: () => [],
    },
  },
  emits: [
    'selectAllConversations',
    'assignAgent',
    'updateConversations',
    'assignLabels',
    'assignTeam',
    'resolveConversations',
    // Dynamically emitted via handleBatchAction
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchMarkRead',
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchMarkUnread',
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchMarkResolved',
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchMarkUnresolved',
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchRemovePriority',
    // eslint-disable-next-line vue/no-unused-emit-declarations
    'batchDelete',
  ],
  data() {
    return {
      showAgentsList: false,
      showUpdateActions: false,
      showLabelActions: false,
      showTeamsList: false,
      showBatchActionsMenu: false,
      popoverPositions: {},
      showCustomTimeSnoozeModal: false,
    };
  },
  computed: {
    batchActionMenuItems() {
      return [
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.MARK_READ'),
          action: 'batchMarkRead',
          value: 'batchMarkRead',
          icon: 'i-lucide-mail-open',
        },
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.MARK_UNREAD'),
          action: 'batchMarkUnread',
          value: 'batchMarkUnread',
          icon: 'i-lucide-mail',
        },
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.MARK_RESOLVED'),
          action: 'batchMarkResolved',
          value: 'batchMarkResolved',
          icon: 'i-lucide-check-circle',
        },
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.MARK_UNRESOLVED'),
          action: 'batchMarkUnresolved',
          value: 'batchMarkUnresolved',
          icon: 'i-lucide-rotate-ccw',
        },
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.REMOVE_PRIORITY'),
          action: 'batchRemovePriority',
          value: 'batchRemovePriority',
          icon: 'i-lucide-flag-off',
        },
        {
          label: this.$t('CHAT_LIST.BATCH_EDIT.DELETE'),
          action: 'delete',
          value: 'batchDelete',
          icon: 'i-lucide-trash-2',
        },
      ];
    },
  },
  mounted() {
    emitter.on(
      CMD_BULK_ACTION_SNOOZE_CONVERSATION,
      this.onCmdSnoozeConversation
    );
    emitter.on(
      CMD_BULK_ACTION_REOPEN_CONVERSATION,
      this.onCmdReopenConversation
    );
    emitter.on(
      CMD_BULK_ACTION_RESOLVE_CONVERSATION,
      this.onCmdResolveConversation
    );
  },
  unmounted() {
    emitter.off(
      CMD_BULK_ACTION_SNOOZE_CONVERSATION,
      this.onCmdSnoozeConversation
    );
    emitter.off(
      CMD_BULK_ACTION_REOPEN_CONVERSATION,
      this.onCmdReopenConversation
    );
    emitter.off(
      CMD_BULK_ACTION_RESOLVE_CONVERSATION,
      this.onCmdResolveConversation
    );
  },
  methods: {
    onCmdSnoozeConversation(snoozeType) {
      if (snoozeType === wootConstants.SNOOZE_OPTIONS.UNTIL_CUSTOM_TIME) {
        this.showCustomTimeSnoozeModal = true;
      } else {
        this.updateConversations('snoozed', findSnoozeTime(snoozeType) || null);
      }
    },
    onCmdReopenConversation() {
      this.updateConversations('open', null);
    },
    onCmdResolveConversation() {
      this.updateConversations('resolved', null);
    },
    customSnoozeTime(customSnoozedTime) {
      this.showCustomTimeSnoozeModal = false;
      if (customSnoozedTime) {
        this.updateConversations('snoozed', getUnixTime(customSnoozedTime));
      }
    },
    hideCustomSnoozeModal() {
      this.showCustomTimeSnoozeModal = false;
    },
    selectAll(e) {
      this.$emit('selectAllConversations', e.target.checked);
    },
    submit(agent) {
      this.$emit('assignAgent', agent);
    },
    updateConversations(status, snoozedUntil) {
      this.$emit('updateConversations', status, snoozedUntil);
    },
    assignLabels(labels) {
      this.$emit('assignLabels', labels);
    },
    assignTeam(team) {
      this.$emit('assignTeam', team);
    },
    resolveConversations() {
      this.$emit('resolveConversations');
    },
    toggleBatchActionsMenu() {
      this.showBatchActionsMenu = !this.showBatchActionsMenu;
    },
    handleBatchAction({ value }) {
      this.showBatchActionsMenu = false;
      this.$emit(value);
    },
    toggleLabelActions() {
      this.showLabelActions = !this.showLabelActions;
    },
    toggleAgentList() {
      this.showAgentsList = !this.showAgentsList;
    },
    toggleTeamsList() {
      this.showTeamsList = !this.showTeamsList;
    },
  },
};
</script>

<template>
  <div class="bulk-action__container">
    <div class="flex items-center justify-between">
      <label class="flex items-center justify-between bulk-action__panel">
        <input
          type="checkbox"
          class="checkbox"
          :checked="allConversationsSelected"
          :indeterminate.prop="!allConversationsSelected"
          @change="selectAll($event)"
        />
        <span>
          {{
            $t('BULK_ACTION.CONVERSATIONS_SELECTED', {
              conversationCount: conversations.length,
            })
          }}
        </span>
      </label>
      <div class="flex items-center gap-1 bulk-action__actions">
        <div
          v-on-clickaway="() => (showBatchActionsMenu = false)"
          class="relative"
        >
          <NextButton
            v-tooltip="$t('CHAT_LIST.BATCH_EDIT.TOGGLE')"
            icon="i-lucide-list-todo"
            slate
            xs
            faded
            :class="showBatchActionsMenu ? 'bg-n-alpha-2' : ''"
            @click="toggleBatchActionsMenu"
          />
          <DropdownMenu
            v-if="showBatchActionsMenu"
            :menu-items="batchActionMenuItems"
            class="ltr:right-0 rtl:left-0 mt-1 w-48 top-full"
            @action="handleBatchAction($event)"
          />
        </div>
        <NextButton
          v-tooltip="$t('BULK_ACTION.LABELS.ASSIGN_LABELS')"
          icon="i-lucide-tags"
          slate
          xs
          faded
          @click="toggleLabelActions"
        />
        <NextButton
          v-tooltip="$t('BULK_ACTION.ASSIGN_AGENT_TOOLTIP')"
          icon="i-lucide-user-round-plus"
          slate
          xs
          faded
          @click="toggleAgentList"
        />
        <NextButton
          v-tooltip="$t('BULK_ACTION.ASSIGN_TEAM_TOOLTIP')"
          icon="i-lucide-users-round"
          slate
          xs
          faded
          @click="toggleTeamsList"
        />
      </div>
      <transition name="popover-animation">
        <LabelActions
          v-if="showLabelActions"
          class="label-actions-box"
          @assign="assignLabels"
          @close="showLabelActions = false"
        />
      </transition>
      <transition name="popover-animation">
        <AgentSelector
          v-if="showAgentsList"
          class="agent-actions-box"
          :selected-inboxes="selectedInboxes"
          :conversation-count="conversations.length"
          @select="submit"
          @close="showAgentsList = false"
        />
      </transition>
      <transition name="popover-animation">
        <TeamActions
          v-if="showTeamsList"
          class="team-actions-box"
          @assign-team="assignTeam"
          @close="showTeamsList = false"
        />
      </transition>
    </div>
    <div v-if="allConversationsSelected" class="bulk-action__alert">
      {{ $t('BULK_ACTION.ALL_CONVERSATIONS_SELECTED_ALERT') }}
    </div>
    <woot-modal
      v-model:show="showCustomTimeSnoozeModal"
      :on-close="hideCustomSnoozeModal"
    >
      <CustomSnoozeModal
        @close="hideCustomSnoozeModal"
        @choose-time="customSnoozeTime"
      />
    </woot-modal>
  </div>
</template>

<style scoped lang="scss">
.bulk-action__container {
  @apply p-3 relative border-b border-solid border-n-strong dark:border-n-weak;
}

.bulk-action__panel {
  @apply cursor-pointer;

  span {
    @apply text-xs my-0 mx-1;
  }

  input[type='checkbox'] {
    @apply cursor-pointer m-0;
  }
}

.bulk-action__alert {
  @apply bg-n-amber-3 text-n-amber-12 rounded text-xs mt-2 py-1 px-2 border border-solid border-n-amber-5;
}

.popover-animation-enter-active,
.popover-animation-leave-active {
  transition: transform ease-out 0.1s;
}

.popover-animation-enter {
  transform: scale(0.95);
  @apply opacity-0;
}

.popover-animation-enter-to {
  transform: scale(1);
  @apply opacity-100;
}

.popover-animation-leave {
  transform: scale(1);
  @apply opacity-100;
}

.popover-animation-leave-to {
  transform: scale(0.95);
  @apply opacity-0;
}

.label-actions-box {
  --triangle-position: 5.3125rem;
}
.update-actions-box {
  --triangle-position: 3.5rem;
}
.agent-actions-box {
  --triangle-position: 1.75rem;
}
.team-actions-box {
  --triangle-position: 0.125rem;
}
</style>
