<script>
export default {
  name: 'CitationPopup',
  props: {
    citation: {
      type: Object,
      default: null,
    },
    position: {
      type: Object,
      default: () => ({ x: 0, y: 0 }),
    },
  },
  emits: ['mouseenter', 'mouseleave'],
  computed: {
    popupStyle() {
      return {
        left: `${this.position.x}px`,
        top: `${this.position.y}px`,
      };
    },
    typeLabel() {
      const typeMap = {
        article: 'Help Center Article',
        web_url: 'Web Source',
        faq: 'FAQ',
        document: 'Document',
      };
      return typeMap[this.citation?.type] || 'Source';
    },
  },
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="citation"
      class="citation-popup"
      :style="popupStyle"
      @mouseenter="$emit('mouseenter')"
      @mouseleave="$emit('mouseleave')"
    >
      <div class="citation-type">
        <svg
          class="type-icon"
          viewBox="0 0 16 16"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="M2 3.5A1.5 1.5 0 0 1 3.5 2h9A1.5 1.5 0 0 1 14 3.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 12.5v-9ZM4.5 5a.5.5 0 0 0 0 1h7a.5.5 0 0 0 0-1h-7Zm0 2.5a.5.5 0 0 0 0 1h7a.5.5 0 0 0 0-1h-7Zm0 2.5a.5.5 0 0 0 0 1h4a.5.5 0 0 0 0-1h-4Z"
            fill="currentColor"
          />
        </svg>
        <span>{{ typeLabel }}</span>
      </div>
      <div class="citation-title">
        <a :href="citation.url" target="_blank" rel="noopener noreferrer">
          {{ citation.title }}
        </a>
      </div>
    </div>
  </Teleport>
</template>
