<script>
import SearchSuggestions from './SearchSuggestions.vue';
import ArticlesAPI from '../api/article';

export default {
  components: {
    SearchSuggestions,
  },
  data() {
    return {
      isOpen: false,
      searchTerm: '',
      isLoading: false,
      searchResults: [],
    };
  },

  computed: {
    portalSlug() {
      return window.portalConfig.portalSlug;
    },
    localeCode() {
      return window.portalConfig.localeCode;
    },
    searchTranslations() {
      const { searchTranslations = {} } = window.portalConfig;
      return searchTranslations;
    },
    searchButtonLabel() {
      return this.searchTranslations.searchButtonLabel || 'Search';
    },
    hasSearchTerm() {
      return this.searchTerm.trim().length > 0;
    },
  },

  watch: {
    isOpen(val) {
      if (val) {
        document.addEventListener('keydown', this.onKeydown);
        this.$nextTick(() => {
          this.$refs.searchInput?.focus();
        });
      } else {
        document.removeEventListener('keydown', this.onKeydown);
      }
    },
  },

  unmounted() {
    clearTimeout(this.typingTimer);
    document.removeEventListener('keydown', this.onKeydown);
  },

  methods: {
    toggleSearch() {
      this.isOpen = !this.isOpen;
      if (!this.isOpen) {
        this.resetSearch();
      }
    },
    openSearch() {
      this.isOpen = true;
    },
    closeSearch() {
      this.isOpen = false;
      this.resetSearch();
    },
    resetSearch() {
      this.searchTerm = '';
      this.searchResults = [];
      this.isLoading = false;
    },
    onKeydown(e) {
      if (e.key === 'Escape') {
        this.closeSearch();
      }
    },
    onSearchInput(e) {
      this.searchTerm = e.target.value;
      if (this.typingTimer) {
        clearTimeout(this.typingTimer);
      }
      this.isLoading = true;
      this.typingTimer = setTimeout(() => {
        this.fetchArticlesByQuery();
      }, 500);
    },
    async fetchArticlesByQuery() {
      if (!this.searchTerm.trim()) {
        this.searchResults = [];
        this.isLoading = false;
        return;
      }
      try {
        this.isLoading = true;
        this.searchResults = [];
        const { data } = await ArticlesAPI.searchArticles(
          this.portalSlug,
          this.localeCode,
          this.searchTerm
        );
        this.searchResults = data.payload;
      } catch (error) {
        // Silently handle search errors
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>

<template>
  <!-- Search trigger button in the header -->
  <div class="relative flex items-center">
    <button
      class="flex items-center gap-1.5 px-1 py-2 text-slate-600 dark:text-slate-300 stroke-slate-600 dark:stroke-slate-300 hover:text-slate-900 dark:hover:text-slate-100 hover:stroke-slate-900 dark:hover:stroke-slate-100 transition-colors"
      type="button"
      :aria-label="searchButtonLabel"
      @click="toggleSearch"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="16"
        height="16"
        viewBox="0 0 16 16"
        fill="none"
      >
        <path
          d="M7.33333 12.6667C10.2789 12.6667 12.6667 10.2789 12.6667 7.33333C12.6667 4.38781 10.2789 2 7.33333 2C4.38781 2 2 4.38781 2 7.33333C2 10.2789 4.38781 12.6667 7.33333 12.6667Z"
          stroke="currentColor"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path
          d="M14 14L11.1 11.1"
          stroke="currentColor"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <span class="text-sm font-medium">{{ searchButtonLabel }}</span>
    </button>

    <!-- Search overlay modal -->
    <teleport to="body">
      <div
        v-if="isOpen"
        class="fixed inset-0 z-[9999] flex items-start justify-center pt-[10vh]"
      >
        <!-- Backdrop -->
        <div
          class="absolute inset-0 bg-black/40 dark:bg-black/60"
          @click="closeSearch"
        />
        <!-- Search panel -->
        <div
          class="relative w-full max-w-2xl mx-4 bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-700 overflow-hidden"
        >
          <!-- Search input area -->
          <div
            class="flex items-center gap-3 px-5 py-4 border-b border-slate-100 dark:border-slate-800"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 16 16"
              fill="none"
              class="flex-shrink-0 text-slate-400 dark:text-slate-500"
            >
              <path
                d="M7.33333 12.6667C10.2789 12.6667 12.6667 10.2789 12.6667 7.33333C12.6667 4.38781 10.2789 2 7.33333 2C4.38781 2 2 4.38781 2 7.33333C2 10.2789 4.38781 12.6667 7.33333 12.6667Z"
                stroke="currentColor"
                stroke-width="1.33333"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <path
                d="M14 14L11.1 11.1"
                stroke="currentColor"
                stroke-width="1.33333"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
            <input
              ref="searchInput"
              :value="searchTerm"
              type="text"
              class="w-full text-base bg-transparent outline-none text-slate-800 dark:text-slate-100 placeholder-slate-400 dark:placeholder-slate-500"
              :placeholder="
                searchTranslations.searchPlaceholder || 'Search articles...'
              "
              role="search"
              @input="onSearchInput"
            />
            <!-- eslint-disable vue/no-bare-strings-in-template -->
            <button
              class="flex-shrink-0 px-2 py-1 text-xs font-medium rounded border border-slate-200 dark:border-slate-600 text-slate-500 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
              @click="closeSearch"
            >
              Esc
            </button>
            <!-- eslint-enable vue/no-bare-strings-in-template -->
          </div>
          <!-- Search results area -->
          <div v-if="hasSearchTerm" class="max-h-[60vh] overflow-y-auto">
            <SearchSuggestions
              :items="searchResults"
              :is-loading="isLoading"
              :search-term="searchTerm"
              :empty-placeholder="searchTranslations.emptyPlaceholder"
              :results-title="searchTranslations.resultsTitle"
              :loading-placeholder="searchTranslations.loadingPlaceholder"
            />
          </div>
        </div>
      </div>
    </teleport>
  </div>
</template>
