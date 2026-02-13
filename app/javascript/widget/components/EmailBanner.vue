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
  components: { FluentIcon, Spinner },
  props: {
    scrollContainer: { type: Object, default: null },
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
      isReady: false,
      scrollInitialized: false,
      lastScrollTop: 0,
      lastSyncedEmail: '',
      scrollDebounceTimer: null,
      bannerWasShown: false,
      stateChangeCooldown: false,
      isAtTop: true,
      showAtTopTemporarily: false,
      atTopTimer: null,
      isHighlighted: false,
      highlightTimer: null,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'contacts/getCurrentUser',
      widgetColor: 'appConfig/getWidgetColor',
      allMessages: 'conversation/getConversation',
    }),
    hasUserSentMessage() {
      return Object.values(this.allMessages).some(
        msg => msg.message_type === MESSAGE_TYPE.INCOMING
      );
    },
    textColor() {
      return getContrastingTextColor(this.widgetColor);
    },
    userEmail() {
      return this.currentUser?.email || '';
    },
    hasEmail() {
      return !!this.userEmail || this.isSaved;
    },
    submitButtonStyle() {
      return this.v$.emailInput.$invalid
        ? { backgroundColor: '#9CA3AF', color: '#fff' }
        : { backgroundColor: this.widgetColor, color: this.textColor };
    },
    inputWrapperStyle() {
      return this.isFocused
        ? {
            borderColor: this.widgetColor,
            boxShadow: `0 0 0 2px ${this.widgetColor}30`,
          }
        : {};
    },
    highlightStyle() {
      if (!this.isHighlighted) return {};
      return { '--highlight-color': this.widgetColor };
    },
    shouldShowBanner() {
      return this.enableEmailCollect && !this.isCollapsed;
    },
    shouldShowOverlay() {
      if (!this.enableEmailCollect) return false;
      // When email is saved (and not recently saved), only show temporarily at top
      if (this.hasEmail && !this.isEditing && !this.recentlySaved) {
        return this.showAtTopTemporarily;
      }
      return !this.isCollapsed || this.hasEmail;
    },
    enableEmailCollect() {
      const enabled = window.chatwootWebChannel?.enableEmailCollect ?? false;
      if (this.bannerWasShown) return enabled;
      return this.isReady && this.hasUserSentMessage && enabled;
    },
  },
  validations: {
    emailInput: { required, email },
  },
  watch: {
    scrollContainer: {
      immediate: true,
      handler(container) {
        if (container) container.addEventListener('scroll', this.handleScroll);
      },
    },
    userEmail: {
      immediate: true,
      handler(newEmail) {
        if (newEmail && newEmail !== this.lastSyncedEmail)
          this.syncEmailFromStore();
      },
    },
    enableEmailCollect(val) {
      if (val && !this.bannerWasShown) this.bannerWasShown = true;
    },
  },
  mounted() {
    emitter.on(ON_CONVERSATION_HANDOFF, this.onConversationHandoff);
    setTimeout(() => {
      this.isReady = true;
      this.syncEmailFromStore();
    }, 300);
  },
  beforeUnmount() {
    this.scrollContainer?.removeEventListener('scroll', this.handleScroll);
    clearTimeout(this.scrollDebounceTimer);
    clearTimeout(this.atTopTimer);
    clearTimeout(this.highlightTimer);
    emitter.off(ON_CONVERSATION_HANDOFF, this.onConversationHandoff);
  },
  methods: {
    handleScroll() {
      if (!this.scrollContainer || !this.isReady) return;

      const currentScrollTop = this.scrollContainer.scrollTop;
      const wasAtTop = this.isAtTop;
      this.isAtTop = currentScrollTop < 10;

      // When email is saved and user scrolls to top, show banner temporarily
      if (this.hasEmail && !this.isEditing && !this.recentlySaved) {
        if (this.isAtTop && !wasAtTop) {
          this.showBannerTemporarily();
        }
        return;
      }

      if (this.stateChangeCooldown) return;

      clearTimeout(this.scrollDebounceTimer);
      this.scrollDebounceTimer = setTimeout(() => this.processScroll(), 100);
    },
    showBannerTemporarily() {
      clearTimeout(this.atTopTimer);
      this.showAtTopTemporarily = true;
      this.atTopTimer = setTimeout(() => {
        this.showAtTopTemporarily = false;
      }, 2000);
    },
    processScroll() {
      if (this.stateChangeCooldown || this.recentlySaved) return;
      if (this.hasEmail) return;

      const currentScrollTop = this.scrollContainer.scrollTop;

      if (!this.scrollInitialized) {
        this.lastScrollTop = currentScrollTop;
        this.scrollInitialized = true;
        return;
      }

      const scrollDelta = currentScrollTop - this.lastScrollTop;
      this.lastScrollTop = currentScrollTop;

      if (Math.abs(scrollDelta) > 50) {
        const wasCollapsed = this.isCollapsed;

        if (scrollDelta > 0 && currentScrollTop > 150) {
          this.isCollapsed = true;
        } else if (scrollDelta < -50) {
          this.isCollapsed = false;
        }

        if (wasCollapsed !== this.isCollapsed) this.startCooldown();
      }
    },
    startCooldown() {
      this.stateChangeCooldown = true;
      setTimeout(() => {
        this.stateChangeCooldown = false;
        if (this.scrollContainer)
          this.lastScrollTop = this.scrollContainer.scrollTop;
      }, 300);
    },
    async onSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      this.isUpdating = true;
      try {
        await ContactsAPI.update({ email: this.emailInput });
        this.isSaved = true;
        this.recentlySaved = true;
        this.isEditing = false;
        this.isCollapsed = false;
        await this.$store.dispatch('contacts/get');
        setTimeout(() => {
          this.recentlySaved = false;
        }, 1500);
      } finally {
        this.isUpdating = false;
      }
    },
    expandBanner() {
      if (this.isCollapsed) {
        this.isCollapsed = false;
        this.startCooldown();
      }
    },
    onConversationHandoff() {
      this.expandBanner();
      this.highlightBanner();
      // Also show temporarily if email is already saved
      if (this.hasEmail && !this.isEditing) {
        this.showBannerTemporarily();
      }
    },
    highlightBanner() {
      clearTimeout(this.highlightTimer);
      this.isHighlighted = true;
      this.highlightTimer = setTimeout(() => {
        this.isHighlighted = false;
      }, 4000);
    },
    onInputFocus() {
      this.isFocused = true;
      if (this.hasEmail) this.isEditing = true;
    },
    onInputBlur() {
      this.isFocused = false;
    },
    onEmailInput() {
      this.v$.emailInput.$touch();
      if (!this.emailInput) this.isEditing = true;
    },
    syncEmailFromStore() {
      const storeEmail = this.currentUser?.email;
      if (storeEmail && storeEmail !== this.lastSyncedEmail) {
        this.lastSyncedEmail = storeEmail;
        this.emailInput = storeEmail;
        this.isSaved = true;
      }
    },
  },
};
</script>

<template>
  <div
    v-if="enableEmailCollect"
    class="email-banner-overlay"
    :class="{ show: shouldShowOverlay }"
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
    <div
      v-else-if="shouldShowBanner"
      class="email-banner"
      :class="{ 'email-banner--highlighted': isHighlighted }"
      :style="highlightStyle"
    >
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
.email-banner-overlay {
  position: fixed;
  top: 52px;
  left: 0;
  width: 100%;
  z-index: 9999;
  opacity: 0;
  visibility: hidden;
  transition:
    opacity 200ms ease,
    visibility 200ms ease;
  pointer-events: none;

  &.show {
    opacity: 1;
    visibility: visible;
    pointer-events: auto;
  }
}

.email-banner {
  @apply mx-5 mt-2 p-2 bg-white dark:bg-n-solid-2 rounded-xl;
  box-shadow:
    0 4px 12px rgba(0, 0, 0, 0.1),
    0 2px 4px rgba(0, 0, 0, 0.06);
  transition:
    box-shadow 0.3s ease,
    transform 0.3s ease;

  &--highlighted {
    animation: email-banner-pulse 1.5s ease-in-out 2;
    box-shadow:
      0 4px 12px rgba(0, 0, 0, 0.1),
      0 2px 4px rgba(0, 0, 0, 0.06),
      0 0 0 3px var(--highlight-color, #1f93ff);
  }
}

@keyframes email-banner-pulse {
  0%,
  100% {
    transform: scale(1);
    box-shadow:
      0 4px 12px rgba(0, 0, 0, 0.1),
      0 2px 4px rgba(0, 0, 0, 0.06),
      0 0 0 3px var(--highlight-color, #1f93ff);
  }
  50% {
    transform: scale(1.02);
    box-shadow:
      0 6px 20px rgba(0, 0, 0, 0.15),
      0 2px 6px rgba(0, 0, 0, 0.08),
      0 0 0 5px var(--highlight-color, #1f93ff),
      0 0 16px var(--highlight-color, #1f93ff);
  }
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
  &::placeholder {
    @apply text-n-slate-9;
  }
  &:read-only {
    @apply cursor-default;
  }

  &:-webkit-autofill,
  &:-webkit-autofill:hover,
  &:-webkit-autofill:focus,
  &:-webkit-autofill:active {
    -webkit-box-shadow: 0 0 0 30px white inset !important;
    -webkit-text-fill-color: inherit !important;
    transition: background-color 5000s ease-in-out 0s;
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
