import { createApp } from 'vue';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { domPurifyConfig } from '../shared/helpers/HTMLSanitizer';
import { directive as onClickaway } from 'vue3-click-away';
import { isSameHost } from '@chatwoot/utils';

import slugifyWithCounter from '@sindresorhus/slugify';
import PublicArticleSearch from './components/PublicArticleSearch.vue';
import TableOfContents from './components/TableOfContents.vue';
import { initializeTheme } from './portalThemeHelper.js';
import { getLanguageDirection } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages.js';

export const getHeadingsfromTheArticle = () => {
  const rows = [];
  const articleElement = document.getElementById('cw-article-content');
  articleElement.querySelectorAll('h1, h2, h3').forEach(element => {
    const slug = slugifyWithCounter(element.innerText);
    element.id = slug;
    element.className = 'scroll-mt-24 heading';
    element.innerHTML += `<a class="permalink text-slate-600 ml-3" href="#${slug}" title="${element.innerText}" data-turbolinks="false">#</a>`;
    rows.push({
      slug,
      title: element.innerText,
      tag: element.tagName.toLowerCase(),
    });
  });
  return rows;
};

export const openExternalLinksInNewTab = () => {
  const { customDomain, hostURL } = window.portalConfig;
  const isOnArticlePage =
    document.querySelector('#cw-article-content') !== null;

  document.addEventListener('click', event => {
    if (!isOnArticlePage) return;

    const link = event.target.closest('a');

    if (link) {
      const currentLocation = window.location.href;
      const linkHref = link.href;

      // Check against current location and custom domains
      const isInternalLink =
        isSameHost(linkHref, currentLocation) ||
        (customDomain && isSameHost(linkHref, customDomain)) ||
        (hostURL && isSameHost(linkHref, hostURL));

      if (!isInternalLink) {
        link.target = '_blank';
        link.rel = 'noopener noreferrer'; // Security and performance benefits
        // Prevent default if you want to stop the link from opening in the current tab
        event.stopPropagation();
      }
    }
  });
};

export const InitializationHelpers = {
  navigateToLocalePage: () => {
    const toggle = document.getElementById('toggle-locale');
    const dropdown = document.getElementById('locale-dropdown');
    
    // Desktop locale dropdown handler
    if (toggle && dropdown) {
      // Toggle locale dropdown
      toggle.addEventListener('click', e => {
        e.stopPropagation();
        dropdown.dataset.dropdownOpen = String(
          dropdown.dataset.dropdownOpen !== 'true'
        );
      });

      document.addEventListener('click', ({ target }) => {
        if (toggle.contains(target)) return;

        // Close the locale dropdown if clicked outside
        if (
          dropdown.dataset.dropdownOpen === 'true' &&
          !dropdown.contains(target)
        ) {
          dropdown.dataset.dropdownOpen = 'false';
        }
      });
    }

    // Handle both desktop and mobile locale button clicks
    document.addEventListener('click', ({ target }) => {
      const localeBtn = target.closest('.locale-menu button[data-locale]');
      const menu = localeBtn?.closest('.locale-menu');

      if (localeBtn && menu) {
        const selectedLocale = localeBtn.dataset.locale;
        const { portalSlug, customDomain, articleTranslations, currentArticleSlug, defaultLocale } = window.portalConfig || {};

        // Save locale preference in cookie (expires in 1 year)
        // Set on parent domain so all subdomains (help.*, chat.*, etc.) can access it
        const expires = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toUTCString();
        const pastDate = 'Thu, 01 Jan 1970 00:00:00 GMT';
        const hostname = window.location.hostname;
        const domain = hostname.split('.').slice(-2).join('.'); // e.g., plantsio.com
        
        // Delete any existing cookies (subdomain-specific and parent domain)
        document.cookie = `help_center_locale=; expires=${pastDate}; path=/`;
        document.cookie = `help_center_locale=; expires=${pastDate}; path=/; domain=${hostname}`;
        document.cookie = `help_center_locale=; expires=${pastDate}; path=/; domain=.${hostname}`;
        document.cookie = `help_center_locale=; expires=${pastDate}; path=/; domain=${domain}`;
        document.cookie = `help_center_locale=; expires=${pastDate}; path=/; domain=.${domain}`;
        
        // Now set the new cookie on parent domain
        document.cookie = `help_center_locale=${selectedLocale}; expires=${expires}; path=/; domain=.${domain}; SameSite=None; Secure`;

        // Close desktop dropdown if open
        if (dropdown) {
          dropdown.dataset.dropdownOpen = 'false';
        }

        // Close mobile menu if this was a mobile click
        if (menu.id === 'mobile-locale-dropdown') {
          setTimeout(() => {
            const mobileToggle = document.getElementById('mobile-menu-toggle');
            if (mobileToggle) mobileToggle.checked = false;
          }, 300);
        }

        // Check if we're on an article page and have translations available
        if (articleTranslations && currentArticleSlug && articleTranslations[selectedLocale]) {
          const translatedSlug = articleTranslations[selectedLocale];
          const includeLocale = selectedLocale !== defaultLocale;
          
          // Navigate to translated article
          if (customDomain) {
            if (includeLocale) {
              window.location.href = `/${encodeURIComponent(selectedLocale)}/articles/${encodeURIComponent(translatedSlug)}`;
            } else {
              window.location.href = `/articles/${encodeURIComponent(translatedSlug)}`;
            }
          } else {
            if (includeLocale) {
              window.location.href = `/hc/${encodeURIComponent(portalSlug)}/${encodeURIComponent(selectedLocale)}/articles/${encodeURIComponent(translatedSlug)}`;
            } else {
              window.location.href = `/hc/${encodeURIComponent(portalSlug)}/articles/${encodeURIComponent(translatedSlug)}`;
            }
          }
        } else {
          // No translation available or not on article page, go to index
          if (customDomain) {
            window.location.href = `/${encodeURIComponent(selectedLocale)}/`;
          } else {
            window.location.href = `/hc/${encodeURIComponent(portalSlug)}/${encodeURIComponent(selectedLocale)}/`;
          }
        }
      }
    });
  },

  initializeSearch: () => {
    const isSearchContainerAvailable = document.querySelector('#search-wrap');
    if (isSearchContainerAvailable) {
      // eslint-disable-next-line vue/one-component-per-file
      const app = createApp({
        components: { PublicArticleSearch },
        template: '<PublicArticleSearch />',
      });

      app.use(VueDOMPurifyHTML, domPurifyConfig);
      app.directive('on-clickaway', onClickaway);
      app.mount('#search-wrap');
    }
  },

  initializeTableOfContents: () => {
    const isOnArticlePage = document.querySelector('#cw-hc-toc');
    if (isOnArticlePage) {
      // eslint-disable-next-line vue/one-component-per-file
      const app = createApp({
        components: { TableOfContents },
        data() {
          return { rows: getHeadingsfromTheArticle() };
        },
        template: '<table-of-contents :rows="rows" />',
      });

      app.use(VueDOMPurifyHTML, domPurifyConfig);
      app.mount('#cw-hc-toc');
    }
  },

  appendPlainParamToURLs: () => {
    [...document.getElementsByTagName('a')].forEach(aTagElement => {
      if (aTagElement.href && aTagElement.href.includes('/hc/')) {
        const url = new URL(aTagElement.href);
        url.searchParams.set('show_plain_layout', 'true');

        aTagElement.setAttribute('href', url);
      }
    });
  },

  setDirectionAttribute: () => {
    const htmlElement = document.querySelector('html');
    // If direction is already applied through props, do not apply again (iframe case)
    const hasDirApplied = htmlElement.getAttribute('data-dir-applied');
    if (!htmlElement || hasDirApplied) return;

    const localeFromHtml = htmlElement.lang;
    htmlElement.dir =
      localeFromHtml && getLanguageDirection(localeFromHtml) ? 'rtl' : 'ltr';
  },

  initializeThemesInPortal: initializeTheme,

  initialize: () => {
    openExternalLinksInNewTab();
    InitializationHelpers.setDirectionAttribute();
    if (window.portalConfig.isPlainLayoutEnabled === 'true') {
      InitializationHelpers.appendPlainParamToURLs();
    } else {
      InitializationHelpers.initializeThemesInPortal();
      InitializationHelpers.navigateToLocalePage();
      InitializationHelpers.initializeSearch();
      InitializationHelpers.initializeTableOfContents();
    }
  },

  onLoad: () => {
    InitializationHelpers.initialize();
    if (window.location.hash) {
      if ('scrollRestoration' in window.history) {
        window.history.scrollRestoration = 'manual';
      }

      const a = document.createElement('a');
      a.href = window.location.hash;
      a['data-turbolinks'] = false;
      a.click();
    }
  },
};
