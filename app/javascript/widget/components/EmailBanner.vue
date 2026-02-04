<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required, email } from '@vuelidate/validators';
import { getContrastingTextColor } from '@chatwoot/utils';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import Spinner from 'shared/components/Spinner.vue';
import ContactsAPI from 'widget/api/contacts';
import { emitter } from 'shared/helpers/mitt';
import { ON_CONVERSATION_HANDOFF } from 'widget/constants/widgetBusEvents';
import { MESSAGE_TYPE } from 'shared/constants/messages';

export default {
  name: 'EmailBanner',
  components: {
    FluentIcon,
    Spinner,
  },
  props: {
    scrollContainer: {
      type: Object,
      default: null,
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      emailInput: '',
      isUpdating: false,
      isCollapsed: false,
      isSaved: false,
      recentlySaved: false,
      isEditing: false,
      isFocused: false,
      handoffTriggered: false,
      isReady: false,
      scrollInitialized: false,
      lastScrollTop: 0,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'contacts/getCurrentUser',
      widgetColor: 'appConfig/getWidgetColor',
      allMessages: 'conversation/getConversation',
    }),
    hasUserSentMessage() {
      const messages = Object.values(this.allMessages);
      return messages.some(msg => msg.message_type === MESSAGE_TYPE.INCOMING);
    },
    textColor() {
      return getContrastingTextColor(this.widgetColor);
    },
    userEmail() {
      return this.currentUser?.email || '';
    },
    hasEmail() {
      // Consider email saved if either store has it or we just saved it locally
      return !!this.userEmail || this.isSaved;
    },
    submitButtonStyle() {
      const isValid = !this.v$.emailInput.$invalid;
      return isValid
        ? { backgroundColor: this.widgetColor, color: this.textColor }
        : { backgroundColor: '#9CA3AF', color: '#fff' };
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
    shouldShowBanner() {
      return this.enableEmailCollect && !this.isCollapsed;
    },
    isSticky() {
      // Sticky when email is not saved, recently saved, or handoff just triggered
      return !this.hasEmail || this.recentlySaved || this.handoffTriggered;
    },
    shouldRender() {
      // Only render after initial ready state is confirmed
      return this.isReady;
    },
    enableEmailCollect() {
      // Check if email collection is enabled and user has sent a message
      if (!this.hasUserSentMessage) return false;
      return window.chatwootWebChannel?.enableEmailCollect ?? false;
    },
  },
  validations: {
    emailInput: {
      required,
      email,
    },
  },
  watch: {
    scrollContainer: {
      immediate: true,
      handler(container) {
        if (container) {
          container.addEventListener('scroll', this.handleScroll);
        }
      },
    },
    userEmail: {
      immediate: true,
      handler(newEmail) {
        if (newEmail) {
          if (!this.emailInput) {
            this.emailInput = newEmail;
          }
          // Sync isSaved state when store has email
          this.isSaved = true;
        }
      },
    },
  },
  mounted() {
    // Listen for conversation handoff events (bot to human agent)
    emitter.on(ON_CONVERSATION_HANDOFF, this.onConversationHandoff);
    // Delay showing banner to prevent flickering during initial load
    // Only set ready once, after initial data has stabilized
    this.initReadyState();
  },
  beforeUnmount() {
    if (this.scrollContainer) {
      this.scrollContainer.removeEventListener('scroll', this.handleScroll);
    }
    emitter.off(ON_CONVERSATION_HANDOFF, this.onConversationHandoff);
  },
  methods: {
    handleScroll() {
      if (!this.scrollContainer || !this.isReady) return;

      const currentScrollTop = this.scrollContainer.scrollTop;

      // Initialize scroll position on first scroll event after ready
      // This prevents reacting to the initial scroll-to-bottom
      if (!this.scrollInitialized) {
        this.lastScrollTop = currentScrollTop;
        this.scrollInitialized = true;
        return;
      }

      // Don't collapse if recently saved (give user time to see the success state)
      if (this.recentlySaved) return;

      const scrollDelta = currentScrollTop - this.lastScrollTop;

      // Only collapse/expand after scrolling more than 50px
      if (Math.abs(scrollDelta) > 50) {
        // Scrolling down - collapse the banner and reset handoff state
        if (scrollDelta > 0 && currentScrollTop > 100) {
          this.isCollapsed = true;
          this.handoffTriggered = false;
        }
        // Scrolling up - expand the banner
        else if (scrollDelta < 0) {
          this.isCollapsed = false;
        }
        this.lastScrollTop = currentScrollTop;
      }
    },
    async onSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      this.isUpdating = true;
      try {
        await ContactsAPI.update({ email: this.emailInput });
        this.isSaved = true;
        this.recentlySaved = true;
        this.isEditing = false;
        // Ensure banner is expanded and visible
        this.isCollapsed = false;
        await this.$store.dispatch('contacts/get');
        // Keep banner visible for 1.5 seconds after save
        setTimeout(() => {
          this.recentlySaved = false;
        }, 1500);
      } catch (error) {
        // Handle error silently
      } finally {
        this.isUpdating = false;
      }
    },
    expandBanner() {
      this.isCollapsed = false;
    },
    onConversationHandoff() {
      // When conversation is handed off from bot to human, show the email banner
      // and keep it fixed on top until user scrolls down
      this.expandBanner();
      this.handoffTriggered = true;
    },
    startEditing() {
      this.isEditing = true;
      this.$nextTick(() => {
        this.$refs.emailInputField?.focus();
        this.$refs.emailInputField?.select();
      });
    },
    onInputFocus() {
      this.isFocused = true;
      if (this.hasEmail) {
        this.isEditing = true;
      }
    },
    onInputBlur() {
      this.isFocused = false;
    },
    onEmailInput() {
      this.v$.emailInput.$touch();
      // If user clears the input, they're editing
      if (!this.emailInput) {
        this.isEditing = true;
      }
    },
    initReadyState() {
      // Wait for DOM and data to stabilize before showing
      // Use requestAnimationFrame + setTimeout to ensure we're past initial render cycles
      requestAnimationFrame(() => {
        setTimeout(() => {
          this.isReady = true;
        }, 100);
      });
    },
  },
};
</script>

<template>
  <div
    v-if="shouldRender && enableEmailCollect"
    class="email-banner-container"
    :class="{ 'is-sticky': isSticky }"
  >
    <!-- Collapsed state - small clickable bar -->
    <div
      v-if="isCollapsed && hasEmail"
      class="email-banner-collapsed"
      @click="expandBanner"
    >
      <FluentIcon icon="mail" size="14" />
      <span class="truncate">{{ userEmail || emailInput }}</span>
      <FluentIcon icon="chevron-down" size="12" />
    </div>

    <!-- Expanded state -->
    <div v-if="shouldShowBanner" class="email-banner">
      <form
        class="email-input-form"
        :class="{ 'is-saved': hasEmail && !isEditing }"
        :style="inputWrapperStyle"
        @submit.prevent="onSubmit"
      >
        <!-- Email icon prefix -->
        <div class="email-icon">
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M3 8L10.89 13.26C11.2187 13.4793 11.6049 13.5963 12 13.5963C12.3951 13.5963 12.7813 13.4793 13.11 13.26L21 8M5 19H19C19.5304 19 20.0391 18.7893 20.4142 18.4142C20.7893 18.0391 21 17.5304 21 17V7C21 6.46957 20.7893 5.96086 20.4142 5.58579C20.0391 5.21071 19.5304 5 19 5H5C4.46957 5 3.96086 5.21071 3.58579 5.58579C3.21071 5.96086 3 6.46957 3 7V17C3 17.5304 3.21071 18.0391 3.58579 18.4142C3.96086 18.7893 4.46957 19 5 19Z"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </div>
        <input
          id="email-banner-input"
          ref="emailInputField"
          v-model="emailInput"
          name="email"
          type="email"
          autocomplete="email"
          :placeholder="$t('EMAIL_BANNER.ENTER_EMAIL')"
          :class="{ error: v$.emailInput.$error }"
          :readonly="hasEmail && !isEditing"
          class="email-input"
          @input="onEmailInput"
          @focus="onInputFocus"
          @blur="onInputBlur"
        />
        <!-- Success icon when saved -->
        <div v-if="hasEmail && !isEditing" class="success-icon">
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M5 12L10 17L19 7"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </div>
        <!-- Submit button -->
        <button
          v-else
          type="submit"
          class="submit-button"
          :disabled="v$.emailInput.$invalid || isUpdating"
          :style="submitButtonStyle"
        >
          <Spinner v-if="isUpdating" size="small" />
          <!-- Arrow icon for submit (upward) -->
          <svg
            v-else
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M12 4L12 20M12 4L6 10M12 4L18 10"
              stroke="white"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </button>
      </form>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.email-banner-container {
  @apply z-10;

  &.is-sticky {
    @apply sticky top-0;
  }
}

.email-banner {
  @apply bg-n-slate-2 dark:bg-n-solid-2 px-3 py-2;
}

.email-banner-collapsed {
  @apply flex items-center gap-2 px-3 py-1.5 bg-n-slate-2 dark:bg-n-solid-2 border-b border-n-weak cursor-pointer text-xs text-n-slate-11;

  &:hover {
    @apply bg-n-slate-3 dark:bg-n-solid-3;
  }
}

.email-input-form {
  @apply flex items-center rounded-lg bg-white dark:bg-n-solid-1 border border-solid border-n-slate-10 dark:border-n-slate-6 transition-all duration-200 py-1.5 px-2;

  &.is-saved {
    @apply bg-n-slate-1 dark:bg-n-solid-2 border-n-slate-4;
  }
}

.email-icon {
  @apply flex-shrink-0 text-n-slate-10;
}

.email-input {
  @apply flex-1 h-7 px-1.5 text-[13px] bg-transparent text-n-slate-12;
  border: none !important;
  outline: none !important;
  box-shadow: none !important;

  &:focus {
    border: none !important;
    outline: none !important;
    box-shadow: none !important;
  }

  /* Disable browser autofill background */
  &:-webkit-autofill,
  &:-webkit-autofill:hover,
  &:-webkit-autofill:focus,
  &:-webkit-autofill:active {
    -webkit-box-shadow: 0 0 0 30px white inset !important;
    -webkit-text-fill-color: inherit !important;
    transition: background-color 5000s ease-in-out 0s;
  }

  &::placeholder {
    @apply text-n-slate-9;
  }

  &:read-only {
    @apply cursor-default;
  }
}

.success-icon {
  @apply h-7 w-7 flex items-center justify-center flex-shrink-0 text-green-600;
}

.submit-button {
  @apply h-7 w-7 flex items-center justify-center rounded-full text-white flex-shrink-0 transition-all duration-200;

  &:hover:not(:disabled) {
    filter: brightness(1.1);
    transform: scale(1.05);
  }

  &:active:not(:disabled) {
    transform: scale(0.95);
  }

  &:disabled {
    @apply opacity-40 cursor-default;
  }
}
</style>
