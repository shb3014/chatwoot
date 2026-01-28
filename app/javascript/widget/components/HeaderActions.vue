<script>
import { mapGetters } from 'vuex';
import { IFrameHelper, RNHelper } from 'widget/helpers/utils';
import { popoutChatWindow } from '../helpers/popoutHelper';
import { sendEmailTranscript } from 'widget/api/conversation';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import configMixin from 'widget/mixins/configMixin';
import { CONVERSATION_STATUS } from 'shared/constants/messages';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

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
    async sendTranscript() {
      try {
        await sendEmailTranscript();
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_SUCCESS'),
        });
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_ERROR'),
        });
      }
      this.showMenu = false;
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="showHeaderActions" class="actions flex items-center gap-2">
    <button
      v-if="showPopoutButton"
      class="button transparent compact new-window--button"
      @click="popoutWindow"
    >
      <FluentIcon icon="open" size="20" class="text-n-slate-11" />
    </button>

    <!-- Menu button -->
    <div v-if="showMenuButton" class="relative">
      <button
        class="header-action-btn"
        :title="$t('OPTIONS')"
        @click="toggleMenu"
      >
        <FluentIcon icon="more-vertical" size="20" class="text-n-slate-11" />
      </button>

      <!-- Dropdown menu -->
      <div v-if="showMenu" v-on-clickaway="closeMenu" class="menu-dropdown">
        <button
          v-if="canShowEndConversation"
          class="menu-item"
          @click="resolveConversation"
        >
          <FluentIcon icon="sign-out" size="16" />
          <span>{{ $t('END_CONVERSATION') }}</span>
        </button>
        <button
          v-if="conversationSize > 0"
          class="menu-item"
          @click="sendTranscript"
        >
          <FluentIcon icon="mail" size="16" />
          <span>{{ $t('EMAIL_TRANSCRIPT.BUTTON_TEXT') }}</span>
        </button>
      </div>
    </div>

    <!-- Close button -->
    <button
      class="header-action-btn close-button"
      :class="{
        'rn-close-button': isRNWebView,
      }"
      :title="$t('CLOSE_WIDGET')"
      @click="closeWindow"
    >
      <FluentIcon icon="dismiss" size="20" class="text-n-slate-11" />
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
  @apply flex items-center justify-center w-8 h-8 rounded-lg transition-colors duration-150;
  @apply hover:bg-n-slate-2 active:bg-n-slate-3;
}

.menu-dropdown {
  @apply absolute right-0 top-full mt-1 py-1 min-w-[180px] bg-white rounded-lg shadow-lg border border-n-weak z-50;
}

.menu-item {
  @apply flex items-center gap-2 w-full px-3 py-2 text-sm text-n-slate-12 transition-colors duration-150;
  @apply hover:bg-n-slate-2;

  &:first-child {
    @apply rounded-t-lg;
  }

  &:last-child {
    @apply rounded-b-lg;
  }
}
</style>
