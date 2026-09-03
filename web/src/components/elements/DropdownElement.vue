<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { post } from '../../api'

const props = defineProps({ element: { type: Object, required: true }, menu: { type: Object, required: true }, page: { type: Object, required: true } })
const open = ref(false)
const trigger = ref(null)
const list = ref(null)
const activeIndex = ref(0)
const placement = ref({})
const options = computed(() => props.element.data.options || [])
const selectedValue = computed(() => props.element.data.value ?? props.element.data.selectedValue)
const selected = computed(() => options.value.find((item) => item.value === selectedValue.value))
const visibleRows = computed(() => Math.max(3, Math.min(10, Number(props.element.data.maxVisibleOptions) || 6)))

async function position() {
  await nextTick()
  const rect = trigger.value?.getBoundingClientRect(); if (!rect) return
  const rowHeight = 42
  const maxHeight = Math.min((visibleRows.value * rowHeight) + 8, window.innerHeight * 0.45)
  const below = window.innerHeight - rect.bottom
  const above = rect.top
  const opensAbove = below < Math.min(maxHeight, 180) && above > below
  placement.value = {
    position: 'fixed', left: `${Math.max(8, Math.min(rect.left, window.innerWidth - rect.width - 8))}px`,
    width: `${rect.width}px`, maxHeight: `${maxHeight}px`,
    top: opensAbove ? 'auto' : `${rect.bottom + 4}px`, bottom: opensAbove ? `${window.innerHeight - rect.top + 4}px` : 'auto',
    '--fm-dropdown-accent': props.menu.config.theme?.accent || '#a73732',
    '--fm-dropdown-bg': props.menu.config.theme?.background || 'rgba(22, 17, 14, .99)',
    '--fm-dropdown-text': props.menu.config.theme?.text || '#f6eee3',
    '--fm-dropdown-muted': props.menu.config.theme?.muted || '#c8b9a5',
  }
}
async function revealActiveOption() {
  await nextTick()
  const container = list.value
  const option = container?.children?.[activeIndex.value]
  if (!container || !option) return
  const optionTop = option.offsetTop
  const optionBottom = optionTop + option.offsetHeight
  if (optionTop < container.scrollTop) container.scrollTop = optionTop
  else if (optionBottom > container.scrollTop + container.clientHeight) container.scrollTop = optionBottom - container.clientHeight
}
function toggle() {
  if (props.element.data.disabled) return
  open.value = !open.value
  if (open.value) {
    const found = options.value.findIndex((item) => item.value === selectedValue.value && !item.disabled)
    activeIndex.value = found >= 0 ? found : Math.max(0, options.value.findIndex((item) => !item.disabled))
    position()
    revealActiveOption()
  }
}
function select(option) {
  if (option?.disabled) return
  open.value = false
  post('elementAction', { menuId: props.menu.menuId, pageId: props.page.pageId, elementId: props.element.elementId, event: 'change', value: option.value })
  trigger.value?.focus()
}
function enabledIndex(start, direction) {
  if (!options.value.length) return -1
  for (let offset = 0; offset < options.value.length; offset += 1) {
    const index = (start + (offset * direction) + options.value.length) % options.value.length
    if (!options.value[index]?.disabled) return index
  }
  return -1
}
function keydown(event) {
  if (!open.value && ['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(event.key)) { toggle(); event.preventDefault(); return }
  if (!open.value) return
  if (event.key === 'Escape') { open.value = false; trigger.value?.focus(); event.preventDefault(); return }
  if (event.key === 'Home') activeIndex.value = enabledIndex(0, 1)
  if (event.key === 'End') activeIndex.value = enabledIndex(options.value.length - 1, -1)
  if (event.key === 'ArrowDown') activeIndex.value = enabledIndex(activeIndex.value + 1, 1)
  if (event.key === 'ArrowUp') activeIndex.value = enabledIndex(activeIndex.value - 1, -1)
  if (['Enter', ' '].includes(event.key) && activeIndex.value >= 0) select(options.value[activeIndex.value])
  event.preventDefault()
}
function outside(event) { if (open.value && !trigger.value?.contains(event.target) && !list.value?.contains(event.target)) open.value = false }
watch(() => [props.menu.activePageId, props.element.data.options, props.element.data.maxVisibleOptions, props.menu.config.theme], () => { if (open.value) position() }, { deep: true })
watch(activeIndex, () => { if (open.value) revealActiveOption() })
window.addEventListener('pointerdown', outside)
window.addEventListener('resize', position)
onBeforeUnmount(() => { window.removeEventListener('pointerdown', outside); window.removeEventListener('resize', position) })
</script>

<template>
  <div class="field dropdown-field">
    <label v-if="element.data.label">{{ element.data.label }}</label>
    <button ref="trigger" data-menu-control class="control dropdown-trigger" role="combobox"
      :aria-expanded="open" :disabled="element.data.disabled" @click="toggle" @keydown.stop="keydown">
      <span>{{ selected?.label ?? selected?.text ?? element.data.placeholder ?? 'Select an option' }}</span><span>▾</span>
    </button>
    <Teleport to="#overlay-root">
      <ul v-if="open" ref="list" class="dropdown-list" role="listbox" :style="placement">
        <li v-if="options.length === 0" class="dropdown-empty">{{ element.data.emptyText || 'No options' }}</li>
        <li v-for="(option, index) in options" :key="String(option.value)" role="option"
          :aria-selected="option.value === selectedValue" :class="{ active: index === activeIndex, selected: option.value === selectedValue, disabled: option.disabled }"
          @pointerenter="activeIndex = index" @click="select(option)">{{ option.label ?? option.text ?? option.value }}</li>
      </ul>
    </Teleport>
  </div>
</template>
