import { addClasses, removeClasses, toggleClass } from './DOMHelpers';
import { IFrameHelper } from './IFrameHelper';
import { isExpandedView } from './settingsHelper';
import {
  CHATWOOT_CLOSED,
  CHATWOOT_OPENED,
} from '../widget/constants/sdkEvents';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';

export const bubbleSVG =
  'M240.808 240.808H122.123C56.6994 240.808 3.45695 187.562 3.45695 122.122C3.45695 56.7031 56.6994 3.45697 122.124 3.45697C187.566 3.45697 240.808 56.7031 240.808 122.122V240.808Z';

// Bubble animation state (declared early as it's used in onBubbleClick)
let hasBubbleAnimations = false;
let openAnimationUrl = '';
let closeAnimationUrl = '';

export const widgetHolder = document.createElement('div');

export const bubbleHolder = document.createElement('div');
export const chatBubble = document.createElement('button');
export const closeBubble = document.createElement('button');
export const notificationBubble = document.createElement('span');

export const setBubbleText = bubbleText => {
  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.getElementById('woot-widget--expanded__text');
    textNode.innerText = bubbleText;
  }
};

export const createBubbleIcon = ({ className, path, target }) => {
  let bubbleClassName = `${className} woot-elements--${window.$chatwoot.position}`;
  const bubbleIcon = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'svg'
  );
  bubbleIcon.setAttributeNS(null, 'id', 'woot-widget-bubble-icon');
  bubbleIcon.setAttributeNS(null, 'width', '24');
  bubbleIcon.setAttributeNS(null, 'height', '24');
  bubbleIcon.setAttributeNS(null, 'viewBox', '0 0 240 240');
  bubbleIcon.setAttributeNS(null, 'fill', 'none');
  bubbleIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

  const bubblePath = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'path'
  );
  bubblePath.setAttributeNS(null, 'd', path);
  bubblePath.setAttributeNS(null, 'fill', '#FFFFFF');

  bubbleIcon.appendChild(bubblePath);
  target.appendChild(bubbleIcon);

  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.createElement('div');
    textNode.id = 'woot-widget--expanded__text';
    textNode.innerText = '';
    target.appendChild(textNode);
    bubbleClassName += ' woot-widget--expanded';
  }

  target.className = bubbleClassName;
  target.title = 'Open chat window';
  return target;
};

export const createBubbleHolder = hideMessageBubble => {
  if (hideMessageBubble) {
    addClasses(bubbleHolder, 'woot-hidden');
  }
  addClasses(bubbleHolder, 'woot--bubble-holder');
  bubbleHolder.id = 'cw-bubble-holder';
  // Support both Turbo (modern) and Turbolinks 5.x (legacy)
  bubbleHolder.dataset.turboPermanent = true;
  bubbleHolder.dataset.turbolinksPermanent = true;

  if (document.body) {
    document.body.appendChild(bubbleHolder);
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      document.body.appendChild(bubbleHolder);
    });
  }
};

const handleBubbleToggle = newIsOpen => {
  IFrameHelper.events.onBubbleToggle(newIsOpen);

  if (newIsOpen) {
    dispatchWindowEvent({ eventName: CHATWOOT_OPENED });
  } else {
    dispatchWindowEvent({ eventName: CHATWOOT_CLOSED });
    chatBubble.focus();
  }
};

export const onBubbleClick = (props = {}) => {
  const { toggleValue } = props;
  const { isOpen } = window.$chatwoot;
  if (isOpen === toggleValue) return;

  const newIsOpen = toggleValue === undefined ? !isOpen : toggleValue;
  window.$chatwoot.isOpen = newIsOpen;

  // When bubble animations are enabled, only use chatBubble (no close button)
  if (hasBubbleAnimations) {
    toggleClass(widgetHolder, 'woot--hide');
  } else {
    // Default behavior: toggle between chatBubble and closeBubble
    toggleClass(chatBubble, 'woot--hide');
    toggleClass(closeBubble, 'woot--hide');
    toggleClass(widgetHolder, 'woot--hide');
  }

  handleBubbleToggle(newIsOpen);
};

export const onClickChatBubble = () => {
  bubbleHolder.addEventListener('click', onBubbleClick);
};

export const addUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  addClasses(holderEl, 'has-unread-view');
};

export const removeUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  removeClasses(holderEl, 'has-unread-view');
};

// Bubble animation helpers
const hideStaticBubbleIcon = bubble => {
  try {
    const svgIcon = bubble && bubble.querySelector('#woot-widget-bubble-icon');
    if (svgIcon) {
      svgIcon.style.opacity = '0';
    }
  } catch (_) {
    // Ignore DOM errors
  }
};

const playAnimation = url => {
  if (!url) return;

  // When animations are enabled, always use the chatBubble (single bubble for all animations)
  const bubble = document.querySelector(
    '.woot-widget-bubble:not(.woot--close)'
  );
  const bubbleId = 'chat';

  if (!bubble) {
    return;
  }

  hideStaticBubbleIcon(bubble);

  // Get existing animation image
  const currentImg = document.getElementById(
    `woot-bubble-animation-${bubbleId}`
  );
  const animationUrl = `${url}?t=${Date.now()}`;

  // Create and preload new image
  const newImg = document.createElement('img');
  newImg.style.cssText = `
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: inherit;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0s ease;
  `;
  newImg.id = `woot-bubble-animation-${bubbleId}`;

  // Preload and swap when ready
  newImg.onload = () => {
    // Remove old image if exists
    if (currentImg && currentImg.parentNode) {
      currentImg.parentNode.removeChild(currentImg);
    }
    // Show new image
    newImg.style.opacity = '1';
  };

  // Add new image to bubble
  bubble.appendChild(newImg);

  // Start loading the animation
  newImg.src = animationUrl;
};

export const setupBubbleAnimations = animationsConfig => {
  if (!animationsConfig) return;

  // Enable single bubble mode when animations are configured
  hasBubbleAnimations = true;

  const { intro_animation_url, open_animation_url, close_animation_url } =
    animationsConfig;
  openAnimationUrl = open_animation_url || '';
  closeAnimationUrl = close_animation_url || '';

  // Play intro animation when bubble first appears
  if (intro_animation_url) {
    playAnimation(intro_animation_url);
  }

  // Setup open/close animations via global events to stay in sync with real state
  // All animations play on the same chatBubble element
  if (openAnimationUrl) {
    try {
      window.addEventListener(CHATWOOT_OPENED, () => {
        playAnimation(openAnimationUrl);
      });
    } catch (_) {
      // Ignore event listener errors
    }
  }

  if (closeAnimationUrl) {
    try {
      window.addEventListener(CHATWOOT_CLOSED, () => {
        playAnimation(closeAnimationUrl);
      });
    } catch (_) {
      // Ignore event listener errors
    }
  }
};
