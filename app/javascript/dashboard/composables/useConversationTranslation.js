import { reactive } from 'vue';
import CaptainTranslation from 'dashboard/api/captain/translation';
import {
  splitTranslatedSegments,
  replaceTextInHtml,
} from 'dashboard/helper/htmlTranslation';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

/**
 * RAM-only translation cache shared across all components.
 * Translations are never persisted to DB — purely for agent reading purposes.
 */
const state = reactive({
  // { [conversationId]: { [messageId]: { content: string, isHtml: boolean } } }
  cache: {},
  // { [conversationId]: boolean } — currently running translation
  translating: {},
  // { [conversationId]: boolean } — translation view is active
  active: {},
  // { [conversationId]: { total: number, done: number } }
  progress: {},
});

/**
 * Pending metadata for messages whose translations are in-flight.
 * Stores { isHtml, originalHtml } so the ActionCable handler can perform
 * HTML text-node replacement when the translation arrives.
 */
const pendingMeta = {};

const ACTIVITY_MESSAGE_TYPE = 2;
const MAX_CONTENT_LENGTH = 8000;

const LOG_PREFIX = '[ConversationTranslation]';

/**
 * Extract translatable content from a message.
 *
 * For email messages with HTML body: extracts only the visible text nodes,
 * joins them with a delimiter. The original HTML is preserved so that after
 * translation the text segments can be spliced back in.
 *
 * For plain-text messages: returns msg.content directly.
 */
function extractTranslatableContent(msg) {
  const content = msg.content || '';

  // For batch translation, always use the plain-text content field.
  // HTML email extraction pulls in quoted replies and signatures that
  // double the token count and translation time. The backend strips
  // quoted content from plain text much more effectively.
  // The translated result is displayed as plain text, which is sufficient
  // for agent reading purposes.
  return {
    content: content.slice(0, MAX_CONTENT_LENGTH),
    isHtml: false,
    originalHtml: null,
  };
}

/**
 * Process a single translated message received from ActionCable.
 * For HTML emails, splices translated text segments back into the original
 * HTML structure. For plain text, stores as-is.
 */
function processTranslationResult(conversationId, messageId, translation) {
  const meta = pendingMeta[conversationId]?.[messageId];
  if (!meta) return;

  let translatedContent = translation;
  let resultIsHtml = meta.isHtml;

  if (meta.isHtml && meta.originalHtml) {
    const segments = splitTranslatedSegments(translation);
    const rebuilt = replaceTextInHtml(meta.originalHtml, segments);
    if (rebuilt) {
      translatedContent = rebuilt;
    } else {
      // eslint-disable-next-line no-console
      console.warn(
        `${LOG_PREFIX} [msg=${messageId}] Segment count mismatch, using plain text fallback`
      );
      resultIsHtml = false;
    }
  }

  if (!state.cache[conversationId]) state.cache[conversationId] = {};
  state.cache[conversationId][messageId] = {
    content: translatedContent,
    isHtml: resultIsHtml,
  };

  if (state.progress[conversationId]) {
    state.progress[conversationId].done += 1;
  }

  // eslint-disable-next-line no-console
  console.log(
    `${LOG_PREFIX} [msg=${messageId}] Received via stream`,
    `(isHtml=${resultIsHtml}, length=${translatedContent.length})`
  );
}

// --- ActionCable event listeners (registered once, module-scoped) ---

let listenersRegistered = false;

function registerBusListeners() {
  if (listenersRegistered) return;
  listenersRegistered = true;

  emitter.on(BUS_EVENTS.TRANSLATION_MESSAGE_COMPLETED, data => {
    const { conversation_id: cid, message_id: mid, translation } = data;
    if (!cid || !mid || !translation) return;
    processTranslationResult(cid, mid, translation);
  });

  emitter.on(BUS_EVENTS.TRANSLATION_BATCH_COMPLETED, data => {
    const { conversation_id: cid, error } = data;
    if (!cid) return;

    state.translating[cid] = false;
    delete pendingMeta[cid];

    if (error) {
      // eslint-disable-next-line no-console
      console.error(
        `${LOG_PREFIX} Batch failed for conversation ${cid}:`,
        error
      );
    } else {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} Batch complete for conversation ${cid}`);
    }
  });
}

/**
 * Composable that manages conversation-level bulk translation via the Captain
 * LLM translation API. Uses a single streaming LLM call for all messages.
 * Results arrive progressively via ActionCable and are cached in a
 * module-level reactive object (RAM only).
 */
export function useConversationTranslation() {
  // Ensure bus listeners are registered on first use
  registerBusListeners();

  /**
   * Translate every translatable message in the conversation in a single
   * streaming LLM call. Already-cached messages are skipped.
   */
  const translateConversation = async (
    conversationId,
    messages,
    targetLanguage
  ) => {
    const translatable = messages.filter(msg => {
      const msgType = msg.message_type ?? msg.messageType;
      if (!msg.content || msgType === ACTIVITY_MESSAGE_TYPE) return false;
      // Skip already-cached messages
      return !state.cache[conversationId]?.[msg.id];
    });

    if (!translatable.length) {
      // eslint-disable-next-line no-console
      console.warn(
        `${LOG_PREFIX} No translatable messages in conversation ${conversationId}`
      );
      return;
    }

    // eslint-disable-next-line no-console
    console.log(
      `${LOG_PREFIX} Starting batch translation for conversation ${conversationId}:`,
      `${translatable.length} messages, target=${targetLanguage}`
    );

    if (!state.cache[conversationId]) state.cache[conversationId] = {};
    state.translating[conversationId] = true;
    state.active[conversationId] = true;
    state.progress[conversationId] = { total: translatable.length, done: 0 };

    // Build batch payload and store pending metadata for HTML replacement
    pendingMeta[conversationId] = {};
    const batchMessages = translatable.map(msg => {
      const { content, isHtml, originalHtml } = extractTranslatableContent(msg);
      pendingMeta[conversationId][msg.id] = { isHtml, originalHtml };
      return { id: msg.id, content };
    });

    try {
      await CaptainTranslation.translateBatch({
        conversationId,
        messages: batchMessages,
        targetLanguage,
      });
      // eslint-disable-next-line no-console
      console.log(
        `${LOG_PREFIX} Batch request accepted for conversation ${conversationId}`
      );
    } catch (error) {
      state.translating[conversationId] = false;
      delete pendingMeta[conversationId];
      // eslint-disable-next-line no-console
      console.error(
        `${LOG_PREFIX} Batch request failed:`,
        error?.response?.status,
        error?.response?.data || error.message
      );
    }
  };

  /**
   * Toggle the translation view on/off for a conversation that already has
   * cached translations.
   */
  const toggleTranslation = conversationId => {
    state.active[conversationId] = !state.active[conversationId];
  };

  /**
   * Remove all cached data for a conversation.
   */
  const clearTranslation = conversationId => {
    delete state.cache[conversationId];
    delete state.translating[conversationId];
    delete state.active[conversationId];
    delete state.progress[conversationId];
    delete pendingMeta[conversationId];
  };

  return {
    state,
    translateConversation,
    toggleTranslation,
    clearTranslation,
  };
}
