# Live Chat Widget Enhancements

This document summarizes the changes made to the Chatwoot live chat widget.

## Overview

The following enhancements were implemented:
1. Email collection banner at the top of chat window
2. Time indication for agent messages
3. Turbolinks compatibility fix for Help Center

---

## 1. Email Collection Banner

### Description
Replaced the old bot message-based email collection with a sleek banner at the top of the chat window.

### Files Modified

#### Backend
- **`app/services/message_templates/template/email_collect.rb`**
  - Disabled the old bot message creation for email collection
  - Method now returns `true` without creating messages

- **`app/views/widgets/show.html.erb`**
  - Added `enableEmailCollect` to the `window.chatwootWebChannel` config object

#### Frontend - Vuex Store
- **`app/javascript/widget/store/modules/appConfig.js`**
  - Added `enableEmailCollect` state, getter, and action

#### Frontend - Components
- **`app/javascript/widget/components/EmailBanner.vue`** (New File)
  - Sticky banner at top of conversation
  - Email input with validation (Vuelidate)
  - Features:
    - Shows after user sends first message
    - Auto-hides on scroll down, reappears on scroll up
    - Success checkmark icon when email is saved
    - Edit functionality to modify email
    - Expands automatically on conversation handoff (bot to human)
    - Matches message input styling (rounded button, same focus effects)
  - Autofill-resistant input styling
  - Proper form attributes (`id`, `name`, `autocomplete`)

- **`app/javascript/widget/components/ConversationWrap.vue`**
  - Integrated `EmailBanner` component
  - Added `latestAgentMessageId` computed property

#### Frontend - Events
- **`app/javascript/widget/constants/widgetBusEvents.js`**
  - Added `ON_CONVERSATION_HANDOFF` event constant

- **`app/javascript/widget/helpers/actionCable.js`**
  - Emits `ON_CONVERSATION_HANDOFF` when conversation status changes to 'open'

#### Frontend - Translations
- **`app/javascript/widget/i18n/locale/en.json`**
  - Added `EMAIL_BANNER.ENTER_EMAIL` translation

### Behavior
- Banner appears after user sends their first message
- Sticky when email not yet saved
- Becomes scrollable after email is saved
- Shows success icon when email is on file
- Auto-expands on handoff from AI agent to human agent

---

## 2. Time Indication for Agent Messages

### Description
Added relative time display (e.g., "Just now", "Minutes ago") after the agent name on the latest agent message.

### Files Modified

- **`app/javascript/widget/components/AgentMessage.vue`**
  - Added `relativeTime` computed property with vague time logic
  - Added `isLatestAgentMessage` prop
  - Added timer mechanism (`timeRefreshKey`) to refresh time every 30 seconds
  - Only shows time on the latest agent message
  - Fade animation when time indicator appears/disappears

- **`app/javascript/widget/components/ChatMessage.vue`**
  - Added `latestAgentMessageId` prop
  - Passes `is-latest-agent-message` to AgentMessage

- **`app/javascript/widget/assets/scss/views/_conversation.scss`**
  - Added `.time-label` styles
  - Added `.fade-time-*` transition animations

- **`app/javascript/widget/i18n/locale/en.json`**
  - Added `AGENT.TIME.JUST_NOW` = "Just now"
  - Added `AGENT.TIME.FEW_MINUTES` = "Minutes ago"

### Time Display Logic
| Time Elapsed | Display |
|--------------|---------|
| < 1 minute | "Just now" |
| < 10 minutes | "Minutes ago" |
| ≥ 10 minutes | Standard format (e.g., "about 15 minutes ago") |

---

## 3. Turbolinks Compatibility Fix

### Description
Fixed an issue where the live chat widget would disappear when navigating between pages in the Help Center (which uses Turbolinks).

### Files Modified

- **`app/javascript/entrypoints/sdk.js`**
  - Removed conditional `if (window.Turbolinks)` check
  - Added null check for `event.data.newBody`
  - Added `turbolinks:load` event listener to ensure widget elements are re-appended to DOM after navigation

### Root Cause
The widget script was checking for `window.Turbolinks` before adding event listeners, but Turbolinks might not be loaded at that point. Additionally, the `turbolinks:before-render` event alone wasn't sufficient.

### Solution
- Always add the event listener (it only fires if Turbolinks is actually used)
- Add a `turbolinks:load` handler that ensures widget elements are in the DOM after navigation completes

---

## Component Architecture

```
ConversationWrap.vue
├── EmailBanner.vue (sticky top banner)
│   ├── Collapsed state (shows email, click to expand)
│   └── Expanded state (input form)
└── ChatMessage.vue
    └── AgentMessage.vue (with time indicator)
```

---

## Configuration

### Enable Email Collection
The email collection banner is controlled by the inbox setting `enable_email_collect`. This setting is passed to the widget via `window.chatwootWebChannel.enableEmailCollect`.

### Widget Settings
```javascript
window.chatwootWebChannel = {
  // ... other settings
  enableEmailCollect: true/false
}
```

---

## CSS Classes

### Email Banner
- `.email-banner-container` - Main container (sticky positioning)
- `.email-banner` - Expanded state wrapper
- `.email-banner-collapsed` - Collapsed state (shows saved email)
- `.email-input-form` - Form container with focus effects
- `.email-input` - Input field (autofill-resistant)
- `.success-icon` - Checkmark icon for saved state
- `.submit-button` - Circular submit button

### Agent Message Time
- `.time-label` - Time text styling
- `.fade-time-enter-active` / `.fade-time-leave-active` - Transition animations

---

## Event Flow

### Email Banner Handoff Detection
```
ActionCable receives "conversation.status_changed"
    ↓
actionCable.js checks if status === 'open'
    ↓
Emits ON_CONVERSATION_HANDOFF via mitt event bus
    ↓
EmailBanner.vue listens and calls expandBanner()
    ↓
Banner becomes visible and sticky for 3 seconds
```

### Time Refresh Mechanism
```
AgentMessage mounted (if isLatestAgentMessage)
    ↓
startTimeRefresh() creates 30-second interval
    ↓
Increments timeRefreshKey
    ↓
relativeTime computed property re-evaluates
    ↓
Timer stopped when component unmounts or no longer latest
```

---

## Known Considerations

1. **Email Banner Flickering**: Fixed by adding `isReady` flag and `scrollInitialized` flag to prevent reactions to initial scroll-to-bottom
2. **Form Autofill**: CSS tricks used to prevent browser autofill from changing input background color
3. **Turbolinks**: Widget elements have `data-turbo-permanent` attribute for persistence
