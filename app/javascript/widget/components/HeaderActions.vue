<script>
import { mapGetters } from 'vuex';
import { IFrameHelper, RNHelper } from 'widget/helpers/utils';
import { popoutChatWindow } from '../helpers/popoutHelper';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import configMixin from 'widget/mixins/configMixin';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

export default {
  name: 'HeaderActions',
  components: { FluentIcon },
  mixins: [configMixin],
  props: {
    showPopoutButton: {
      type: Boolean,
      default: false,
    },
    showEndConversationButton: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return {
      showMenu: false,
    };
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      canUserEndConversation: 'appConfig/getCanUserEndConversation',
      conversationSize: 'conversation/getConversationSize',
      groupedConversation: 'conversation/getGroupedConversation',
    }),
    canLeaveConversation() {
      return [
        CONVERSATION_STATUS.OPEN,
        CONVERSATION_STATUS.SNOOZED,
        CONVERSATION_STATUS.PENDING,
      ].includes(this.conversationStatus);
    },
    isIframe() {
      return IFrameHelper.isIFrame();
    },
    isRNWebView() {
      return RNHelper.isRNWebView();
    },
    showHeaderActions() {
      return this.isIframe || this.isRNWebView || this.hasWidgetOptions;
    },
    conversationStatus() {
      return this.conversationAttributes.status;
    },
    hasWidgetOptions() {
      return this.showPopoutButton || this.conversationStatus === 'open';
    },
    showMenuButton() {
      // Only show menu inside the conversation view
      return this.$route?.name === 'messages' && this.conversationSize > 0;
    },
    hasMenuItems() {
      return this.canShowEndConversation || this.conversationSize > 0;
    },
    canShowEndConversation() {
      return (
        this.canLeaveConversation &&
        this.canUserEndConversation &&
        this.hasEndConversationEnabled &&
        this.showEndConversationButton
      );
    },
  },
  methods: {
    popoutWindow() {
      this.closeWindow();
      const {
        location: { origin },
        chatwootWebChannel: { websiteToken },
        authToken,
      } = window;
      popoutChatWindow(
        origin,
        websiteToken,
        this.$root.$i18n.locale,
        authToken
      );
    },
    closeWindow() {
      if (IFrameHelper.isIFrame()) {
        IFrameHelper.sendMessage({ event: 'closeWindow' });
      } else if (RNHelper.isRNWebView) {
        RNHelper.sendMessage({ type: 'close-widget' });
      }
    },
    resolveConversation() {
      this.$store.dispatch('conversation/resolveConversation');
      this.showMenu = false;
    },
    toggleMenu() {
      this.showMenu = !this.showMenu;
    },
    closeMenu() {
      this.showMenu = false;
    },
    downloadTranscript() {
      const transcript = this.generateTranscriptText();
      const blob = new Blob([transcript], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `chat-transcript-${new Date().toISOString().slice(0, 10)}.txt`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
      this.showMenu = false;
    },
    generateTranscriptText() {
      const lines = [];
      lines.push('Chat Transcript');
      lines.push('='.repeat(50));
      lines.push('');

      this.groupedConversation.forEach(group => {
        lines.push(`--- ${group.date} ---`);
        lines.push('');

        group.messages.forEach(message => {
          const time = new Date(message.created_at * 1000).toLocaleTimeString();
          // message_type 0 = incoming (user), 1 = outgoing (agent)
          const sender =
            message.message_type === 0
              ? 'You'
              : message.sender?.name || 'Agent';
          const content = message.content || '[Attachment]';
          lines.push(`[${time}] ${sender}: ${content}`);
        });
        lines.push('');
      });

      return lines.join('\n');
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="showHeaderActions" class="actions flex items-center gap-2">
    <button
      v-if="showPopoutButton"
      class="button transparent compact new-window--button group"
      @click="popoutWindow"
    >
      <FluentIcon
        icon="open"
        size="18"
        class="text-n-slate-11 transition-colors duration-150 group-hover:text-n-slate-12"
      />
    </button>

    <!-- Menu button -->
    <div v-if="showMenuButton" class="relative">
      <button
        class="header-action-btn group"
        :title="$t('OPTIONS')"
        @click="toggleMenu"
      >
        <FluentIcon
          icon="more-vertical"
          size="18"
          class="text-n-slate-11 transition-colors duration-150 group-hover:text-n-slate-12"
        />
      </button>

      <!-- Dropdown menu -->
      <div v-if="showMenu" v-on-clickaway="closeMenu" class="menu-dropdown">
        <button
          v-if="canShowEndConversation"
          class="menu-item"
          @click="resolveConversation"
        >
          <FluentIcon icon="sign-out" size="18" type="outline" />
          <span>{{ $t('END_CONVERSATION') }}</span>
        </button>
        <button
          v-if="conversationSize > 0"
          class="menu-item"
          @click="downloadTranscript"
        >
          <svg
            class="menu-icon"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <circle
              cx="12"
              cy="12"
              r="9"
              stroke="currentColor"
              stroke-width="2"
            />
            <path
              d="M12 7v8m0 0l-3-3m3 3l3-3"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <span>{{ $t('DOWNLOAD_TRANSCRIPT') }}</span>
        </button>
      </div>
    </div>

    <!-- Close button -->
    <button
      class="header-action-btn close-button group"
      :class="{
        'rn-close-button': isRNWebView,
      }"
      :title="$t('CLOSE_WIDGET')"
      @click="closeWindow"
    >
      <FluentIcon
        icon="dismiss"
        size="18"
        class="text-n-slate-11 transition-colors duration-150 group-hover:text-n-slate-12"
      />
    </button>
  </div>
</template>

<style scoped lang="scss">
.actions {
  .close-button {
    display: flex;
  }
}

.header-action-btn {
  @apply flex items-center justify-center w-7 h-7 rounded-lg transition-colors duration-150;
  @apply hover:bg-n-slate-2 active:bg-n-slate-3;
}

.menu-dropdown {
  @apply absolute right-0 top-full mt-1 py-1 min-w-[160px] bg-white rounded-lg shadow-lg border border-n-weak z-50;
}

.menu-item {
  @apply flex items-center gap-2.5 w-full px-3 py-2 text-xs text-n-slate-11 transition-colors duration-150 whitespace-nowrap;
  @apply hover:bg-n-slate-2 hover:text-n-slate-12;

  svg {
    @apply flex-shrink-0;
  }

  &:first-child {
    @apply rounded-t-lg;
  }

  &:last-child {
    @apply rounded-b-lg;
  }
}

.menu-icon {
  width: 18px;
  height: 18px;
}
</style>
