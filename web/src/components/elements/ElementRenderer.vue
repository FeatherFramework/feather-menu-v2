<script setup>
  import { computed, inject, onBeforeUnmount, ref, watch } from "vue";
  import { post } from "../../api";
  import DropdownElement from "./DropdownElement.vue";

  const props = defineProps({
    element: { type: Object, required: true },
    menu: { type: Object, required: true },
    page: { type: Object, required: true },
  });
  const data = computed(() => props.element.data || {});
  const pageUi = inject('menuPageUi', null);
  const draftKey = JSON.stringify([props.page.pageId, props.element.elementId]);
  const savedDraft = pageUi?.drafts.get(draftKey);
  const initialValue = savedDraft && JSON.stringify(savedDraft.base) === JSON.stringify(data.value.value)
    ? savedDraft.value : data.value.value ?? (['number', 'slider'].includes(props.element.type) ? data.value.min ?? 0 : '');
  const localValue = ref(initialValue);
  const gridPointerId = ref(null);
  let commitSequence = 0;
  onBeforeUnmount(() => {
    if (pageUi && gridPointerId.value === null) pageUi.drafts.set(draftKey, {
      pageId: props.page.pageId, elementId: props.element.elementId,
      base: data.value.value === undefined ? undefined : JSON.parse(JSON.stringify(data.value.value)),
      value: localValue.value === undefined ? undefined : JSON.parse(JSON.stringify(localValue.value)),
    });
  });
  watch(
    () => data.value.value,
    (value) => {
      if (value !== undefined) localValue.value = value;
    },
  );
  const options = computed(() => (data.value.options || []).map((option) => typeof option === 'object' ? option : { value: option, label: String(option) }));
  const displayOption = (option) => option?.label ?? option?.display ?? option?.text ?? option?.value ?? option;
  const currentIndex = computed(() => {
    const byValue = options.value.findIndex((option) => (option?.value ?? option) === localValue.value);
    return byValue >= 0 ? byValue : Math.max(0, Number(data.value.value ?? data.value.start ?? 0));
  });
  const progress = computed(() => {
    const min = Number(data.value.min ?? 0),
      max = Number(data.value.max ?? 100),
      value = Number(data.value.value ?? min);
    return max === min ? 100 : Math.max(0, Math.min(100, ((value - min) / (max - min)) * 100));
  });

  async function emit(event = "activate", value = localValue.value, meta) {
    const sequence = ++commitSequence;
    const result = await post("elementAction", { menuId: props.menu.menuId, pageId: props.page.pageId, elementId: props.element.elementId, event, value, meta });
    if (sequence !== commitSequence) return;
    if (result?.ok === false) localValue.value = data.value.value ?? '';
    else if (data.value.persist === false && result && Object.prototype.hasOwnProperty.call(result, 'value')) localValue.value = result.value;
  }
  function set(value, event = "change") {
    localValue.value = value;
    emit(event, value);
  }
  function arrow(direction) {
    if (!options.value.length) return;
    for (let offset = 1; offset <= options.value.length; offset += 1) {
      const index = (currentIndex.value + direction * offset + options.value.length) % options.value.length;
      if (!options.value[index].disabled) { set(options.value[index].value, "change"); break; }
    }
  }
  function pageArrow(direction) {
    emit(direction < 0 ? "previous" : "next", direction);
  }
  function gridValue(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    const y = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height));
    return { x: x * Number(data.value.maxx ?? 1), y: y * Number(data.value.maxy ?? 1) };
  }
  function startGrid(event) {
    if (data.value.disabled || event.button !== 0) return;
    gridPointerId.value = event.pointerId;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    localValue.value = gridValue(event);
    event.preventDefault();
  }
  function moveGrid(event) {
    if (gridPointerId.value !== event.pointerId) return;
    localValue.value = gridValue(event);
  }
  function finishGrid(event) {
    if (gridPointerId.value !== event.pointerId) return;
    localValue.value = gridValue(event);
    gridPointerId.value = null;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    emit("change", localValue.value);
  }
  function cancelGrid(event) {
    if (gridPointerId.value === event.pointerId) { gridPointerId.value = null; localValue.value = data.value.value; }
  }
  function commitNumber(event) {
    const input = event.target;
    if (!Number.isFinite(input.valueAsNumber)) { localValue.value = data.value.value ?? data.value.min ?? 0; input.value = localValue.value; return; }
    const value = Math.max(data.value.min ?? 0, Math.min(data.value.max ?? 100, input.valueAsNumber));
    input.value = value; set(value);
  }
  function keyGrid(event) {
    const directions = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    const direction = directions[event.key];
    if (!direction || data.value.disabled) return;
    const maxx = Number(data.value.maxx ?? 1), maxy = Number(data.value.maxy ?? 1);
    const stepx = Number(data.value.stepx ?? data.value.step ?? maxx / 100);
    const stepy = Number(data.value.stepy ?? data.value.step ?? maxy / 100);
    set({
      x: Math.max(0, Math.min(maxx, Number(localValue.value?.x || 0) + (direction[0] * stepx))),
      y: Math.max(0, Math.min(maxy, Number(localValue.value?.y || 0) + (direction[1] * stepy))),
    });
    event.preventDefault();
  }
</script>

<template>
  <div class="element-anchor" :data-element-id="element.elementId">
    <h1 v-if="element.type === 'header'" class="heading">{{ data.value }}</h1>
    <h2 v-else-if="element.type === 'subheader'" class="subheading">{{ data.value }}</h2>
    <hr v-else-if="element.type === 'line'" class="line" />
    <div v-else-if="element.type === 'bottomline'" class="bottom-line" />
    <div v-else-if="element.type === 'spacer'" :class="['spacer', `spacer-${data.size || 'medium'}`]" />
    <p v-else-if="element.type === 'textdisplay'" class="text-display">{{ data.value }}</p>

    <button
      v-else-if="element.type === 'button'"
      data-menu-control
      class="control button"
      :disabled="data.disabled"
      @click="emit('activate', data.value)"
    >
      {{ data.label }}
    </button>

    <label v-else-if="element.type === 'input' || element.type === 'number'" class="field">
      <span v-if="data.label">{{ data.label }}</span>
      <input
        data-menu-control
        class="control"
        :type="element.type === 'number' ? 'number' : 'text'"
        :value="localValue"
        :placeholder="data.placeholder"
        :disabled="data.disabled"
        :min="element.type === 'number' ? data.min ?? 0 : undefined"
        :max="element.type === 'number' ? data.max ?? 100 : undefined"
        :step="element.type === 'number' ? data.step ?? 1 : undefined"
        :maxlength="data.maxLength"
        :aria-label="data.label || data.placeholder || (element.type === 'number' ? 'Number' : 'Text')"
        @input="localValue = element.type === 'number' ? $event.target.valueAsNumber : $event.target.value"
        @change="element.type === 'number' ? commitNumber($event) : emit('change')"
      />
    </label>

    <label v-else-if="element.type === 'textarea'" class="field">
      <span v-if="data.label">{{ data.label }}</span>
      <textarea
        data-menu-control
        class="control"
        :value="localValue"
        :rows="data.rows || 4"
        :placeholder="data.placeholder"
        :disabled="data.disabled"
        :maxlength="data.maxLength"
        :aria-label="data.label || data.placeholder || 'Text'"
        @input="localValue = $event.target.value"
        @change="emit('change')"
      />
    </label>

    <label v-else-if="element.type === 'slider'" class="field">
      <span
        >{{ data.label }} <output>{{ localValue }}</output></span
      >
      <input
        data-menu-control
        class="range"
        type="range"
        :value="localValue"
        :min="data.min ?? 0"
        :max="data.max ?? 100"
        :step="data.step ?? data.steps ?? 1"
        :disabled="data.disabled"
        @input="set($event.target.valueAsNumber, 'change')"
      />
    </label>

    <div v-else-if="element.type === 'toggle' || element.type === 'checkbox'" class="field inline-field">
      <span>{{ data.label }}</span>
      <button
        data-menu-control
        :class="['control', 'boolean', { checked: !!localValue }]"
        :role="element.type === 'checkbox' ? 'checkbox' : 'switch'"
        :aria-label="data.label || element.type"
        :aria-checked="!!localValue"
        :disabled="data.disabled"
        @click="set(!localValue)"
      >
        {{ localValue ? data.onLabel || "On" : data.offLabel || "Off" }}
      </button>
    </div>

    <div v-else-if="element.type === 'arrows'" class="field">
      <span v-if="data.label">{{ data.label }}</span>
      <div class="arrow-control">
        <button data-menu-control :disabled="data.disabled" :aria-label="`Previous ${data.label || 'option'}`" @click="arrow(-1)">‹</button> <span>{{ displayOption(options[currentIndex]) }}</span
        ><button data-menu-control :disabled="data.disabled" :aria-label="`Next ${data.label || 'option'}`" @click="arrow(1)">›</button>
      </div>
    </div>

    <DropdownElement v-else-if="element.type === 'dropdown'" :element="element" :menu="menu" :page="page" />

    <fieldset v-else-if="element.type === 'radio'" class="field radio-group" :disabled="data.disabled">
      <legend>{{ data.label }}</legend>
      <label v-for="option in options" :key="`${typeof option.value}:${String(option.value)}`"
        ><input
          data-menu-control
          type="radio"
          :name="element.elementId"
          :value="option.value"
          :checked="option.value === localValue"
          :disabled="option.disabled"
          @change="set(option.value)"
        /><span>{{ displayOption(option) }}</span></label
      >
    </fieldset>

    <div v-else-if="element.type === 'progress'" class="field progress-field">
      <span
        >{{ data.label }} <output>{{ data.text ?? `${Math.round(progress)}%` }}</output></span
      >
      <div class="progress" role="progressbar" :aria-label="data.label || 'Progress'" :aria-valuemin="data.min ?? 0" :aria-valuemax="data.max ?? 100" :aria-valuenow="data.value ?? data.min ?? 0">
        <i :style="{ width: `${progress}%` }" />
      </div>
    </div>

    <div v-else-if="element.type === 'colorpicker'" class="field palette">
      <span>{{ data.label }}</span>
      <div class="palette-options">
        <button
          v-for="color in options"
          :key="`${typeof color.value}:${String(color.value)}`"
          data-menu-control
          :class="{ selected: (color.value ?? color) === localValue }"
          :style="{ background: color.color ?? color.value ?? color }"
          :aria-label="color.label ?? String(color.value ?? color)"
          :aria-pressed="color.value === localValue"
          :disabled="data.disabled || color.disabled"
          @click="set(color.value ?? color)"
        />
      </div>
    </div>

    <div v-else-if="element.type === 'gridslider'" class="field">
      <span>{{ data.label }}</span>
      <button
        data-menu-control
        :class="['grid-slider', { dragging: gridPointerId !== null }]"
        :disabled="data.disabled"
        :aria-label="data.label || 'Two-axis slider'"
        @pointerdown="startGrid"
        @pointermove="moveGrid"
        @pointerup="finishGrid"
        @pointercancel="cancelGrid"
        @keydown="keyGrid"
      >
        <i
          :style="{
            left: `${(Number(localValue?.x || 0) / Number(data.maxx || 1)) * 100}%`,
            top: `${(Number(localValue?.y || 0) / Number(data.maxy || 1)) * 100}%`,
          }"
        />
      </button>
    </div>

    <div v-else-if="element.type === 'pagearrows'" class="page-arrows">
      <button data-menu-control aria-label="Previous page" :disabled="data.disabled || data.current <= 1" @click="pageArrow(-1)">‹</button><span>{{ data.current }}/{{ data.total }}</span
      ><button data-menu-control aria-label="Next page" :disabled="data.disabled || data.current >= data.total" @click="pageArrow(1)">›</button>
    </div>

    <button
      v-else-if="element.type === 'imagebox'"
      data-menu-control
      class="image-box"
      :disabled="data.disabled"
      @click="emit('activate', data.value)"
    >
      <img :src="data.image || data.img" :alt="data.alt || data.label || ''" /><span>{{ data.label }}</span>
    </button>

    <div v-else-if="element.type === 'imageboxcontainer'" class="image-grid">
      <button
        v-for="item in data.items || []"
        :key="item.key || item.value"
        data-menu-control
        class="image-box"
        :disabled="data.disabled || item.disabled"
        @click="emit('child', item.value, { child: item })"
      >
        <img :src="item.image || item.img" :alt="item.alt || item.label || ''" /><span>{{ item.label }}</span>
      </button>
    </div>
  </div>
</template>
