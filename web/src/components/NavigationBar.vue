<script setup>
import { computed } from 'vue'
import { post } from '../api'
const props = defineProps({ menu: { type: Object, required: true } })
const items = computed(() => (props.menu.navigation?.pages || []).filter((item) => !item.hidden))
const currentIndex = computed(() => items.value.findIndex((item) => item.pageId === props.menu.activePageId))
function choose(item, index) {
  if (item.disabled || (props.menu.navigation.type === 'stepper' && props.menu.navigation.allowDirectStep === false)) return
  post('navigationIntent', {
    menuId: props.menu.menuId, mode: props.menu.navigation.type,
    fromPageId: props.menu.activePageId, toPageId: item.pageId,
    action: props.menu.navigation.type === 'tabs' ? 'select' : 'step', index,
  })
}
function step(action) {
  const target = items.value[currentIndex.value + (action === 'back' ? -1 : 1)]
  if (target?.disabled) return
  post('navigationIntent', {
    menuId: props.menu.menuId, mode: 'stepper', fromPageId: props.menu.activePageId,
    toPageId: target?.pageId, action: action === 'next' && !target ? 'finish' : action,
    index: currentIndex.value,
  })
}
</script>
<template>
  <nav :class="['navigation', `navigation-${menu.navigation.type}`]"
    :style="menu.navigation.type === 'stepper' ? { '--step-count': items.length } : undefined"
    :aria-label="menu.navigation.type === 'tabs' ? 'Sections' : 'Progress'">
    <button v-for="(item, index) in items" :key="item.pageId" data-menu-control
      :class="{ active: item.pageId === menu.activePageId, complete: item.complete || index < currentIndex, invalid: item.invalid }"
      :aria-current="item.pageId === menu.activePageId ? 'step' : undefined"
      :disabled="item.disabled || (menu.navigation.type === 'stepper' && menu.navigation.allowDirectStep === false)" @click="choose(item, index)">
      <span v-if="menu.navigation.type === 'stepper'" class="step-number">{{ index + 1 }}</span>
      {{ item.label }}
    </button>
  </nav>
  <div v-if="menu.navigation.type === 'stepper'" class="stepper-actions">
    <button v-if="currentIndex > 0" data-menu-control class="stepper-back" :disabled="items[currentIndex - 1]?.disabled" @click="step('back')">{{ menu.navigation.backLabel || 'Back' }}</button>
    <button data-menu-control class="stepper-next" :disabled="items[currentIndex + 1]?.disabled" @click="step('next')">{{ currentIndex === items.length - 1 ? (menu.navigation.finishLabel || 'Finish') : (menu.navigation.nextLabel || 'Next') }}</button>
  </div>
</template>
