<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ChatCard from 'shared/components/ChatCard.vue';
import ChatForm from 'shared/components/ChatForm.vue';
import ChatOptions from 'shared/components/ChatOptions.vue';
import ChatArticle from './template/Article.vue';
import EmailInput from './template/EmailInput.vue';
import CustomerSatisfaction from 'shared/components/CustomerSatisfaction.vue';
import IntegrationCard from './template/IntegrationCard.vue';
import CitationPopup from './CitationPopup.vue';

export default {
  name: 'AgentMessageBubble',
  components: {
    ChatArticle,
    ChatCard,
    ChatForm,
    ChatOptions,
    EmailInput,
    CustomerSatisfaction,
    IntegrationCard,
    CitationPopup,
  },
  props: {
    message: { type: String, default: null },
    contentType: { type: String, default: null },
    messageType: { type: Number, default: null },
    messageId: { type: Number, default: null },
    isStreamingThinking: { type: Boolean, default: false },
    messageContentAttributes: {
      type: Object,
      default: () => {},
    },
  },
  setup() {
    const { formatMessage, getPlainText, truncateMessage, highlightContent } =
      useMessageFormatter();
    return {
      formatMessage,
      getPlainText,
      truncateMessage,
      highlightContent,
    };
  },
  data() {
    return {
      activeCitation: null,
      citationPosition: { x: 0, y: 0 },
      citationHideTimeout: null,
    };
  },
  computed: {
    isTemplate() {
      return this.messageType === 3;
    },
    isTemplateEmail() {
      return this.contentType === 'input_email';
    },
    isCards() {
      return this.contentType === 'cards';
    },
    isOptions() {
      return this.contentType === 'input_select';
    },
    isForm() {
      return this.contentType === 'form';
    },
    isArticle() {
      return this.contentType === 'article';
    },
    isCSAT() {
      return this.contentType === 'input_csat';
    },
    isIntegrations() {
      return this.contentType === 'integrations';
    },
  },
  mounted() {
    this.$nextTick(() => {
      this.setupCitationListeners();
    });
  },
  updated() {
    this.$nextTick(() => {
      this.setupCitationListeners();
    });
  },
  methods: {
    onResponse(messageResponse) {
      this.$store.dispatch('message/update', messageResponse);
    },
    onOptionSelect(selectedOption) {
      this.onResponse({
        submittedValues: [selectedOption],
        messageId: this.messageId,
      });
    },
    onFormSubmit(formValues) {
      const formValuesAsArray = Object.keys(formValues).map(key => ({
        name: key,
        value: formValues[key],
      }));
      this.onResponse({
        submittedValues: formValuesAsArray,
        messageId: this.messageId,
      });
    },
    setupCitationListeners() {
      const bubbleEl = this.$el?.querySelector('.chat-bubble');
      if (!bubbleEl) return;

      const citations = bubbleEl.querySelectorAll('.citation-chip');
      citations.forEach(chip => {
        chip.removeEventListener('mouseenter', this.handleCitationEnter);
        chip.removeEventListener('mouseleave', this.handleCitationLeave);
        chip.addEventListener('mouseenter', this.handleCitationEnter);
        chip.addEventListener('mouseleave', this.handleCitationLeave);
      });
    },
    handleCitationEnter(event) {
      // Clear any pending hide timeout
      if (this.citationHideTimeout) {
        clearTimeout(this.citationHideTimeout);
        this.citationHideTimeout = null;
      }
      const chip = event.target;
      const rect = chip.getBoundingClientRect();
      this.citationPosition = {
        x: rect.left + rect.width / 2,
        y: rect.top,
      };
      this.activeCitation = {
        ref: chip.dataset.ref,
        title: chip.dataset.title,
        url: chip.dataset.url,
        type: chip.dataset.type,
      };
      this.$nextTick(() => {
        this.adjustPopupPositionWithinWidget();
      });
    },
    handleCitationLeave() {
      // Delay hiding to allow mouse to move to popup
      this.citationHideTimeout = setTimeout(() => {
        this.activeCitation = null;
      }, 100);
    },
    handlePopupEnter() {
      // Cancel hide when mouse enters popup
      if (this.citationHideTimeout) {
        clearTimeout(this.citationHideTimeout);
        this.citationHideTimeout = null;
      }
    },
    handlePopupLeave() {
      // Hide popup when mouse leaves it
      this.activeCitation = null;
    },
    adjustPopupPositionWithinWidget() {
      const popup = document.querySelector('.citation-popup');
      if (!popup) return;

      // Widget runs inside an iframe, so use window dimensions
      const widgetWidth = window.innerWidth;
      const padding = 12;

      // Calculate max width that fits in widget
      const maxWidth = Math.max(160, widgetWidth - padding * 2);
      popup.style.maxWidth = `${maxWidth}px`;

      // Also constrain min-width for narrow widgets to prevent overflow
      const minWidth = Math.min(200, maxWidth);
      popup.style.minWidth = `${minWidth}px`;

      // Force reflow to get accurate dimensions after style changes
      // eslint-disable-next-line no-unused-expressions
      popup.offsetWidth;
      const popupRect = popup.getBoundingClientRect();

      // Horizontal positioning
      // CSS uses transform: translateX(-50%), so popup extends halfWidth to each side of x
      let x = this.citationPosition.x;
      const halfWidth = popupRect.width / 2;

      // Calculate bounds ensuring popup stays within widget viewport
      const minX = padding + halfWidth;
      const maxX = widgetWidth - padding - halfWidth;

      if (maxX >= minX) {
        // Widget is wide enough, clamp x within bounds
        x = Math.min(Math.max(x, minX), maxX);
      } else {
        // Widget is narrower than popup, center it
        x = widgetWidth / 2;
      }

      // Vertical positioning
      let y = this.citationPosition.y;
      const popupTop = y - popupRect.height - 8;
      if (popupTop < padding) {
        // Not enough room above, position below the citation
        y = popupRect.height + padding + 8;
      }

      this.citationPosition = { x, y };
    },
  },
};
</script>

<template>
  <div class="chat-bubble-wrap">
    <div
      v-if="
        !isCards && !isOptions && !isForm && !isArticle && !isCards && !isCSAT
      "
      class="chat-bubble agent text-n-slate-12"
    >
      <div v-if="isStreamingThinking" class="message-content text-n-slate-12">
        <span class="thinking-text">{{ $t('AGENT.THINKING') }}</span>
        <span class="thinking-dots" aria-hidden="true">
          <span class="thinking-dot" />
          <span class="thinking-dot" />
          <span class="thinking-dot" />
        </span>
      </div>
      <div
        v-else
        v-dompurify-html="formatMessage(message, false)"
        class="message-content text-n-slate-12"
      />
      <EmailInput
        v-if="isTemplateEmail"
        :message-id="messageId"
        :message-content-attributes="messageContentAttributes"
      />

      <IntegrationCard
        v-if="isIntegrations"
        :message-id="messageId"
        :meeting-data="messageContentAttributes.data"
      />
      <CitationPopup
        :citation="activeCitation"
        :position="citationPosition"
        @mouseenter="handlePopupEnter"
        @mouseleave="handlePopupLeave"
      />
    </div>
    <div v-if="isOptions">
      <ChatOptions
        :title="message"
        :options="messageContentAttributes.items"
        :hide-fields="!!messageContentAttributes.submitted_values"
        @option-select="onOptionSelect"
      />
    </div>
    <ChatForm
      v-if="isForm && !messageContentAttributes.submitted_values"
      :items="messageContentAttributes.items"
      :button-label="messageContentAttributes.button_label"
      :submitted-values="messageContentAttributes.submitted_values"
      @submit="onFormSubmit"
    />
    <div v-if="isCards">
      <ChatCard
        v-for="item in messageContentAttributes.items"
        :key="item.title"
        :media-url="item.media_url"
        :title="item.title"
        :description="item.description"
        :actions="item.actions"
      />
    </div>
    <div v-if="isArticle">
      <ChatArticle :items="messageContentAttributes.items" />
    </div>
    <CustomerSatisfaction
      v-if="isCSAT"
      :message-content-attributes="messageContentAttributes.submitted_values"
      :display-type="messageContentAttributes.display_type"
      :message="message"
      :message-id="messageId"
    />
  </div>
</template>

<style scoped lang="scss">
.thinking-dot {
  animation: typing-bounce 1.2s infinite;
  background-color: currentColor;
  border-radius: 999px;
  display: inline-block;
  height: 0.25rem;
  width: 0.25rem;
}

.thinking-dots {
  display: inline-flex;
  gap: 0.125rem;
  margin-left: 0.25rem;
}

.thinking-dot:nth-child(2) {
  animation-delay: 0.2s;
}

.thinking-dot:nth-child(3) {
  animation-delay: 0.4s;
}

@keyframes typing-bounce {
  0%,
  80%,
  100% {
    opacity: 0.2;
  }
  40% {
    opacity: 1;
  }
}
</style>
