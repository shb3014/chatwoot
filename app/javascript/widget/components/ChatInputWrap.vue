<script>
import { mapGetters } from 'vuex';

import ChatAttachmentButton from 'widget/components/ChatAttachment.vue';
import configMixin from '../mixins/configMixin';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import ResizableTextArea from 'shared/components/ResizableTextArea.vue';

import EmojiInput from 'shared/components/emoji/EmojiInput.vue';

export default {
  name: 'ChatInputWrap',
  components: {
    ChatAttachmentButton,
    EmojiInput,
    FluentIcon,
    ResizableTextArea,
  },
  mixins: [configMixin],
  props: {
    onSendMessage: {
      type: Function,
      default: () => {},
    },
    onSendAttachment: {
      type: Function,
      default: () => {},
    },
  },
  data() {
    return {
      userInput: '',
      showEmojiPicker: false,
      isFocused: false,
    };
  },

  computed: {
    ...mapGetters({
      widgetColor: 'appConfig/getWidgetColor',
      isWidgetOpen: 'appConfig/getIsWidgetOpen',
      shouldShowFilePicker: 'appConfig/getShouldShowFilePicker',
      shouldShowEmojiPicker: 'appConfig/getShouldShowEmojiPicker',
    }),
    showAttachment() {
      return this.shouldShowFilePicker && this.hasAttachmentsEnabled;
    },
    hasInput() {
      return this.userInput.trim().length > 0;
    },
    sendButtonStyle() {
      return this.hasInput
        ? { backgroundColor: this.widgetColor }
        : { backgroundColor: '#9CA3AF' };
    },
    inputWrapperStyle() {
      if (this.isFocused) {
        return {
          borderColor: this.widgetColor,
          boxShadow: `0 0 0 2px ${this.widgetColor}30`,
        };
      }
      return {};
    },
  },
  watch: {
    isWidgetOpen(isWidgetOpen) {
      if (isWidgetOpen) {
        this.focusInput();
      }
    },
  },
  unmounted() {
    document.removeEventListener('keypress', this.handleEnterKeyPress);
  },
  mounted() {
    document.addEventListener('keypress', this.handleEnterKeyPress);
    if (this.isWidgetOpen) {
      this.focusInput();
    }
  },

  methods: {
    onBlur() {
      this.isFocused = false;
    },
    onFocus() {
      this.isFocused = true;
    },
    handleButtonClick() {
      if (this.userInput && this.userInput.trim()) {
        this.onSendMessage(this.userInput);
      }
      this.userInput = '';
      this.focusInput();
    },
    handleEnterKeyPress(e) {
      if (e.keyCode === 13 && !e.shiftKey) {
        e.preventDefault();
        this.handleButtonClick();
      }
    },
    toggleEmojiPicker() {
      this.showEmojiPicker = !this.showEmojiPicker;
    },
    hideEmojiPicker(e) {
      if (this.showEmojiPicker) {
        e.stopPropagation();
        this.toggleEmojiPicker();
      }
    },
    emojiOnClick(emoji) {
      this.userInput = `${this.userInput}${emoji} `;
    },
    onTypingOff() {
      this.toggleTyping('off');
    },
    onTypingOn() {
      this.toggleTyping('on');
    },
    toggleTyping(typingStatus) {
      this.$store.dispatch('conversation/toggleUserTyping', { typingStatus });
    },
    focusInput() {
      this.$refs.chatInput.focus();
    },
  },
};
</script>

<template>
  <div
    class="flex flex-col rounded-[12px] transition-all duration-200 bg-white border border-solid border-[rgb(80,80,80)]"
    :style="inputWrapperStyle"
    @keydown.esc="hideEmojiPicker"
  >
    <!-- Text input area -->
    <div class="px-3 pt-2">
      <ResizableTextArea
        id="chat-input"
        ref="chatInput"
        v-model="userInput"
        :min-height="1.5"
        :rows="1"
        :aria-label="$t('CHAT_PLACEHOLDER')"
        :placeholder="$t('CHAT_PLACEHOLDER')"
        class="user-message-input reset-base"
        @typing-off="onTypingOff"
        @typing-on="onTypingOn"
        @focus="onFocus"
        @blur="onBlur"
      />
    </div>

    <!-- Bottom bar with buttons -->
    <div class="flex items-center justify-between px-2 pb-2 min-h-8">
      <!-- Left side: attachment and emoji buttons -->
      <div class="flex items-center gap-0.5 min-h-8">
        <ChatAttachmentButton
          v-if="showAttachment"
          class="icon-button text-n-slate-11 hover:text-n-slate-12"
          :on-attach="onSendAttachment"
        />
        <button
          v-if="shouldShowEmojiPicker && hasEmojiPickerEnabled"
          class="icon-button text-n-slate-11 hover:text-n-slate-12"
          :aria-label="$t('EMOJI.ARIA_LABEL')"
          @click="toggleEmojiPicker"
        >
          <FluentIcon
            icon="emoji"
            size="18"
            class="transition-all duration-150"
            :class="{
              'text-n-slate-11': !showEmojiPicker,
              'text-n-brand': showEmojiPicker,
            }"
          />
        </button>
        <EmojiInput
          v-if="shouldShowEmojiPicker && showEmojiPicker"
          v-on-clickaway="hideEmojiPicker"
          :on-click="emojiOnClick"
          @keydown.esc="hideEmojiPicker"
        />
      </div>

      <!-- Right side: send button -->
      <button
        type="submit"
        class="send-button"
        :style="sendButtonStyle"
        :disabled="!hasInput"
        @click="handleButtonClick"
      >
        <svg
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="M12 4L12 20M12 4L6 10M12 4L18 10"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </button>
    </div>
  </div>
</template>

<style scoped lang="scss">
.emoji-dialog {
  @apply max-w-full ltr:right-5 rtl:right-[unset] rtl:left-5 -top-[302px] before:ltr:right-2.5 before:rtl:right-[unset] before:rtl:left-2.5;
}

.user-message-input {
  @apply border-none outline-none w-full placeholder:text-n-slate-10 resize-none h-6 min-h-6 max-h-40 py-0 px-0 bg-n-background text-n-slate-12 text-[13px] leading-relaxed transition-all duration-200;
}

.icon-button {
  @apply flex items-center justify-center w-7 h-7 rounded-md transition-all duration-150;

  &:hover {
    @apply bg-n-slate-2;
  }

  &:active {
    transform: scale(0.95);
  }
}

.send-button {
  @apply flex items-center justify-center w-8 h-8 rounded-full text-white transition-all duration-200;

  &:hover:not(:disabled) {
    filter: brightness(1.1);
    transform: scale(1.05);
  }

  &:active:not(:disabled) {
    transform: scale(0.95);
  }

  &:disabled {
    @apply cursor-default;
  }
}
</style>
