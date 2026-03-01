<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const getters = useStoreGetters();

const inboxes = computed(() => getters['inboxes/getInboxes'].value || []);

const ATTRIBUTES = [
  {
    key: 'content',
    name: () => t('LABEL_MGMT.FORM.HARD_RULES.ATTRIBUTES.CONTENT'),
    inputType: 'text',
  },
  {
    key: 'mail_subject',
    name: () => t('LABEL_MGMT.FORM.HARD_RULES.ATTRIBUTES.MAIL_SUBJECT'),
    inputType: 'text',
  },
  {
    key: 'email',
    name: () => t('LABEL_MGMT.FORM.HARD_RULES.ATTRIBUTES.EMAIL'),
    inputType: 'text',
  },
  {
    key: 'inbox_id',
    name: () => t('LABEL_MGMT.FORM.HARD_RULES.ATTRIBUTES.INBOX_ID'),
    inputType: 'select',
  },
];

const OPERATORS = {
  text: [
    {
      value: 'contains',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.CONTAINS'),
    },
    {
      value: 'does_not_contain',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.DOES_NOT_CONTAIN'),
    },
    {
      value: 'equal_to',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.EQUAL_TO'),
    },
    {
      value: 'not_equal_to',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.NOT_EQUAL_TO'),
    },
    {
      value: 'is_present',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.IS_PRESENT'),
    },
    {
      value: 'is_not_present',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.IS_NOT_PRESENT'),
    },
  ],
  select: [
    {
      value: 'equal_to',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.EQUAL_TO'),
    },
    {
      value: 'not_equal_to',
      label: () => t('LABEL_MGMT.FORM.HARD_RULES.OPERATORS.NOT_EQUAL_TO'),
    },
  ],
};

const NO_VALUE_OPERATORS = ['is_present', 'is_not_present'];

const getAttributeConfig = key =>
  ATTRIBUTES.find(a => a.key === key) || ATTRIBUTES[0];

const getOperators = attrKey => {
  const config = getAttributeConfig(attrKey);
  return OPERATORS[config.inputType] || OPERATORS.text;
};

const needsValueInput = operator => !NO_VALUE_OPERATORS.includes(operator);

const rules = computed({
  get: () => props.modelValue || [],
  set: val => emit('update:modelValue', val),
});

const addCondition = () => {
  const newRule = {
    attribute_key: 'content',
    filter_operator: 'contains',
    values: [],
    query_operator: rules.value.length > 0 ? 'AND' : null,
  };
  rules.value = [...rules.value, newRule];
};

const removeCondition = index => {
  const updated = [...rules.value];
  updated.splice(index, 1);
  if (updated.length > 0 && updated[0].query_operator) {
    updated[0] = { ...updated[0], query_operator: null };
  }
  rules.value = updated;
};

const updateRule = (index, field, value) => {
  const updated = [...rules.value];
  const rule = { ...updated[index] };

  if (field === 'attribute_key') {
    const config = getAttributeConfig(value);
    const ops = OPERATORS[config.inputType] || OPERATORS.text;
    rule.attribute_key = value;
    rule.filter_operator = ops[0].value;
    rule.values = [];
  } else if (field === 'filter_operator') {
    rule.filter_operator = value;
    if (NO_VALUE_OPERATORS.includes(value)) {
      rule.values = [];
    }
  } else if (field === 'values') {
    rule.values = value;
  } else if (field === 'query_operator') {
    rule.query_operator = value;
  }

  updated[index] = rule;
  rules.value = updated;
};

const getValueString = rule => (rule.values || []).join(', ');

const setValueString = (index, str) => {
  const values = str
    .split(',')
    .map(v => v.trim())
    .filter(Boolean);
  updateRule(index, 'values', values);
};
</script>

<template>
  <div class="w-full">
    <label class="block text-sm font-medium mb-1">
      {{ $t('LABEL_MGMT.FORM.HARD_RULES.LABEL') }}
    </label>

    <div v-if="rules.length" class="flex flex-col gap-2 mb-2">
      <template v-for="(rule, index) in rules" :key="index">
        <div
          v-if="index > 0"
          class="flex items-center justify-center relative my-1"
        >
          <hr class="absolute w-full border-b border-solid border-n-weak" />
          <select
            :value="rule.query_operator"
            class="relative w-auto mb-0 text-sm bg-n-background text-n-slate-12 border-n-weak"
            @change="updateRule(index, 'query_operator', $event.target.value)"
          >
            <option value="AND">
              {{ $t('LABEL_MGMT.FORM.HARD_RULES.QUERY_OPERATOR.AND') }}
            </option>
            <option value="OR">
              {{ $t('LABEL_MGMT.FORM.HARD_RULES.QUERY_OPERATOR.OR') }}
            </option>
          </select>
        </div>

        <div
          class="p-2 border border-solid rounded-lg bg-n-background border-n-weak"
        >
          <div class="flex gap-1 items-center">
            <select
              :value="rule.attribute_key"
              class="max-w-[30%] mb-0 text-sm"
              @change="updateRule(index, 'attribute_key', $event.target.value)"
            >
              <option
                v-for="attr in ATTRIBUTES"
                :key="attr.key"
                :value="attr.key"
              >
                {{ attr.name() }}
              </option>
            </select>

            <select
              :value="rule.filter_operator"
              class="max-w-[25%] mb-0 text-sm"
              @change="
                updateRule(index, 'filter_operator', $event.target.value)
              "
            >
              <option
                v-for="op in getOperators(rule.attribute_key)"
                :key="op.value"
                :value="op.value"
              >
                {{ op.label() }}
              </option>
            </select>

            <div v-if="needsValueInput(rule.filter_operator)" class="flex-grow">
              <select
                v-if="
                  getAttributeConfig(rule.attribute_key).inputType === 'select'
                "
                :value="(rule.values || [])[0] || ''"
                class="mb-0 text-sm"
                @change="updateRule(index, 'values', [$event.target.value])"
              >
                <option value="" disabled>
                  {{ $t('LABEL_MGMT.FORM.HARD_RULES.VALUE') }}
                </option>
                <option
                  v-for="inbox in inboxes"
                  :key="inbox.id"
                  :value="String(inbox.id)"
                >
                  {{ inbox.name }}
                </option>
              </select>
              <input
                v-else
                type="text"
                class="!mb-0 text-sm bg-n-background text-n-slate-12 border-n-weak"
                :placeholder="$t('LABEL_MGMT.FORM.HARD_RULES.VALUE')"
                :value="getValueString(rule)"
                @input="setValueString(index, $event.target.value)"
              />
            </div>

            <NextButton
              v-tooltip.top="$t('LABEL_MGMT.FORM.HARD_RULES.DELETE_CONDITION')"
              icon="i-lucide-x"
              slate
              ghost
              xs
              type="button"
              class="flex-shrink-0"
              @click="removeCondition(index)"
            />
          </div>
        </div>
      </template>
    </div>

    <NextButton
      icon="i-lucide-plus"
      :label="$t('LABEL_MGMT.FORM.HARD_RULES.ADD_CONDITION')"
      faded
      slate
      xs
      type="button"
      @click="addCondition"
    />
    <p class="text-xs text-n-slate-10 mt-1">
      {{ $t('LABEL_MGMT.FORM.HARD_RULES.HELP') }}
    </p>
  </div>
</template>
