<script setup>
import { defineProps, defineEmits, computed, ref } from 'vue';
import ArticleListItem from './ArticleListItem.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { searchArticles } from 'widget/api/article';
import { debounce } from '@chatwoot/utils';
import { getMatchingLocale } from 'shared/helpers/portalHelper';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  articles: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['view', 'viewAll']);

const widgetColor = useMapGetter('appConfig/getWidgetColor');
const i18n = useI18n();

const searchQuery = ref('');
const searchResults = ref([]);
const isSearching = ref(false);

const portal = computed(() => window.chatwootWebChannel.portal);

const locale = computed(() => {
  const { locale: selectedLocale } = i18n;
  if (!portal.value || !portal.value.config) return null;
  const { allowed_locales: allowedLocales } = portal.value.config;
  return getMatchingLocale(selectedLocale.value, allowedLocales);
});

const articlesToDisplay = computed(() => {
  if (searchQuery.value) {
    return searchResults.value;
  }
  return props.articles.slice(0, 6);
});

const showNoResults = computed(() => {
  return (
    searchQuery.value && !isSearching.value && searchResults.value.length === 0
  );
});

const performSearch = async query => {
  if (!query.trim()) {
    searchResults.value = [];
    isSearching.value = false;
    return;
  }

  try {
    isSearching.value = true;
    const { data } = await searchArticles(
      portal.value.slug,
      locale.value,
      query
    );
    searchResults.value = data.payload || [];
  } catch (error) {
    searchResults.value = [];
  } finally {
    isSearching.value = false;
  }
};

const debouncedSearch = debounce(performSearch, 500, false);

const onSearchInput = event => {
  searchQuery.value = event.target.value;
  if (searchQuery.value) {
    debouncedSearch(searchQuery.value);
  } else {
    searchResults.value = [];
    isSearching.value = false;
  }
};

const onArticleClick = link => {
  emit('view', link);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <h3 class="font-medium text-n-slate-12">
      {{ $t('PORTAL.POPULAR_ARTICLES') }}
    </h3>

    <!-- 搜索框 -->
    <div class="relative flex items-center bg-slate-100 rounded-lg px-3 py-1 transition-colors duration-200 hover:bg-[rgba(10,168,154,0.08)] focus-within:bg-[rgba(10,168,154,0.08)] group">
      <input
        type="text"
        :value="searchQuery"
        :placeholder="$t('PORTAL.SEARCH_ARTICLES')"
        class="flex-1 bg-transparent text-sm text-slate-700 placeholder:text-slate-400 focus:outline-none focus:text-[rgb(10,168,154)] transition-colors duration-200"
        @input="onSearchInput"
      />
      <svg
        class="w-4 h-4 ml-2 text-slate-400 transition-colors duration-200 group-hover:text-[rgb(10,168,154)] group-focus-within:text-[rgb(10,168,154)]"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
        />
      </svg>
    </div>

    <!-- 文章列表 -->
    <div class="flex flex-col gap-4">
      <div v-if="isSearching" class="text-center py-8 text-n-slate-10 text-sm">
        {{ $t('PORTAL.SEARCHING') }}
      </div>
      <div
        v-else-if="showNoResults"
        class="text-center py-8 text-n-slate-10 text-sm"
      >
        {{ $t('PORTAL.NO_RESULTS') }}
      </div>
      <ArticleListItem
        v-else
        v-for="article in articlesToDisplay"
        :key="article.slug"
        :link="article.link"
        :title="article.title"
        @select-article="onArticleClick"
      />
    </div>
    <div v-if="!searchQuery">
      <button
        class="font-medium tracking-wide inline-flex"
        :style="{ color: widgetColor }"
        @click="$emit('viewAll')"
      >
        <span>{{ $t('PORTAL.VIEW_ALL_ARTICLES') }}</span>
      </button>
    </div>
  </div>
</template>
