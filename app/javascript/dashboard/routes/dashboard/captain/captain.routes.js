import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { frontendURL } from '../../../helper/URLHelper';
import AssistantIndex from './assistants/Index.vue';
import AssistantEdit from './assistants/Edit.vue';
// import AssistantSettings from './assistants/settings/Settings.vue';
import AssistantInboxesIndex from './assistants/inboxes/Index.vue';
import AssistantGuardrailsIndex from './assistants/guardrails/Index.vue';
import AssistantGuidelinesIndex from './assistants/guidelines/Index.vue';
import AssistantScenariosIndex from './assistants/scenarios/Index.vue';
// DocumentsIndex route hidden — data preserved in DB but UI replaced by Sources
// import DocumentsIndex from './documents/Index.vue';
import SourcesIndex from './sources/Index.vue';
import SourcesEdit from './sources/Edit.vue';
import ConversationsIndex from './conversations/Index.vue';
// ResponsesIndex route hidden — replaced by Sources
// import ResponsesIndex from './responses/Index.vue';
import CustomToolsIndex from './tools/Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/captain/assistants'),
    component: AssistantIndex,
    name: 'captain_assistants_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/assistants/:assistantId'),
    component: AssistantEdit,
    name: 'captain_assistants_edit',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/assistants/:assistantId/inboxes'
    ),
    component: AssistantInboxesIndex,
    name: 'captain_assistants_inboxes_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/assistants/:assistantId/guardrails'
    ),
    component: AssistantGuardrailsIndex,
    name: 'captain_assistants_guardrails_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/assistants/:assistantId/scenarios'
    ),
    component: AssistantScenariosIndex,
    name: 'captain_assistants_scenarios_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/assistants/:assistantId/guidelines'
    ),
    component: AssistantGuidelinesIndex,
    name: 'captain_assistants_guidelines_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/sources'),
    component: SourcesIndex,
    name: 'captain_sources_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/sources/:sourceId/edit'),
    component: SourcesEdit,
    name: 'captain_sources_edit',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/conversations'),
    component: ConversationsIndex,
    name: 'captain_conversations_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/captain/tools'),
    component: CustomToolsIndex,
    name: 'captain_tools_index',
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.CAPTAIN_V2,
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
];
