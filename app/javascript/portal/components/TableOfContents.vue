<script>
export default {
  props: {
    rows: {
      type: Array,
      default: () => [],
    },
  },
  data() {
    return {
      currentSlug: this.readSlugFromHash(),
      intersectionObserver: null,
    };
  },
  computed: {
    h1Count() {
      return this.rows.filter(el => el.tag === 'h1').length;
    },
    h2Count() {
      return this.rows.filter(el => el.tag === 'h2').length;
    },
  },
  mounted() {
    this.initializeIntersectionObserver();
    window.addEventListener('hashchange', this.onURLHashChange);
  },
  unmounted() {
    window.removeEventListener('hashchange', this.onURLHashChange);
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
    }
  },
  methods: {
    getClassName(el) {
      if (el.tag === 'h1') {
        return '';
      }
      if (el.tag === 'h2') {
        if (this.h1Count > 0) {
          return 'ltr:ml-2 rtl:mr-2';
        }
        return '';
      }

      if (el.tag === 'h3') {
        if (!this.h1Count && !this.h2Count) {
          return '';
        }
        return 'ltr:ml-5 rtl:mr-5';
      }

      return '';
    },
    initializeIntersectionObserver() {
      // The IntersectionObserver is only used as a "something changed
      // around the headings" trigger. The actual active heading is then
      // computed from real positions (getBoundingClientRect), which avoids
      // two issues with the naive `entries.find(isIntersecting)` approach:
      //   1. `entries` only contains headings whose visibility *changed*
      //      in this tick, not everything currently on screen. When a
      //      lower heading scrolled into view, the active state used to
      //      jump to it even though the previous one was still visible
      //      at the top of the viewport.
      //   2. The entry order is not guaranteed to be document order, so
      //      bulk scrolls (e.g. clicking a TOC link) could pick the wrong
      //      heading.
      this.intersectionObserver = new IntersectionObserver(
        () => {
          this.updateActiveSlug();
        },
        {
          threshold: 0,
        }
      );

      this.rows.forEach(el => {
        const sectionElement = document.getElementById(el.slug);
        if (!sectionElement) return;
        this.intersectionObserver.observe(sectionElement);
      });

      // Compute once on mount in case everything is already in view and
      // the observer would otherwise not fire until the user scrolls.
      this.updateActiveSlug();
    },
    updateActiveSlug() {
      // Active heading = the *last* heading whose top is at or above the
      // trigger line. The trigger line sits just below the sticky header,
      // matching the `scroll-mt-24` (96px) offset applied to headings, so
      // a heading that was just scrolled into the top of the page counts
      // as "passed" and becomes active immediately.
      const triggerLine = 120;
      let lastPassed = null;
      for (const row of this.rows) {
        const el = document.getElementById(row.slug);
        if (!el) continue;
        if (el.getBoundingClientRect().top <= triggerLine) {
          lastPassed = row;
        } else {
          // rows are in document order, anything after is below the line
          break;
        }
      }
      if (lastPassed && lastPassed.slug !== this.currentSlug) {
        this.currentSlug = lastPassed.slug;
      }
    },
    onURLHashChange() {
      this.currentSlug = this.readSlugFromHash();
    },
    readSlugFromHash() {
      const rawHash = window.location?.hash?.substring(1) || '';
      if (!rawHash) return '';
      try {
        // Decode so non-ASCII (e.g. CJK) slugs match the raw element ids
        return decodeURIComponent(rawHash);
      } catch {
        return rawHash;
      }
    },
    isElementActive(el) {
      return this.currentSlug === el.slug;
    },
    elementBorderStyles(el) {
      if (this.isElementActive(el)) {
        return 'border-slate-400 dark:border-slate-50 transition-colors duration-200';
      }
      return 'border-slate-100 dark:border-slate-800';
    },
    elementTextStyles(el) {
      if (this.isElementActive(el)) {
        return 'text-slate-900 dark:text-slate-25 transition-colors duration-200';
      }
      return 'text-slate-700 dark:text-slate-100';
    },
  },
};
</script>

<template>
  <div
    class="hidden lg:block flex-1 py-6 scroll-mt-24 ltr:pl-4 rtl:pr-4 sticky top-24"
  >
    <div v-if="rows.length > 0" class="py-2 overflow-auto">
      <nav class="max-w-2xl">
        <ol
          role="list"
          class="flex flex-col gap-2 text-base ltr:border-l-2 rtl:border-r-2 border-solid border-slate-100 dark:border-slate-800"
        >
          <li
            v-for="element in rows"
            :key="element.slug"
            class="leading-6 ltr:border-l-2 rtl:border-r-2 relative ltr:-left-0.5 rtl:-right-0.5 border-solid"
            :class="elementBorderStyles(element)"
          >
            <p class="py-1 px-3" :class="getClassName(element)">
              <a
                :href="`#${element.slug}`"
                data-turbolinks="false"
                class="font-medium text-sm tracking-[0.28px] cursor-pointer"
                :class="elementTextStyles(element)"
              >
                {{ element.title }}
              </a>
            </p>
          </li>
        </ol>
      </nav>
    </div>
  </div>
</template>
