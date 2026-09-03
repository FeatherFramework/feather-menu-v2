<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import ElementRenderer from './elements/ElementRenderer.vue'
import NavigationBar from './NavigationBar.vue'
import { post } from '../api'

const props = defineProps({ menu: { type: Object, required: true } })
const shell = ref(null)
const dragging = ref(false)
const position = ref()
const dimensions = ref()
const dragOffset = { x: 0, y: 0 }
let resizing = false

const page = computed(() => props.menu.pages[props.menu.activePageId])
const elements = computed(() => page.value?.elementOrder.map((id) => page.value.elements[id]).filter(Boolean) || [])
const inSlot = (slot) => elements.value.filter((element) => (element.data.slot || 'content') === slot)
const theme = computed(() => props.menu.config.theme || {})
const size = computed(() => props.menu.config.size || {})
const resizeEnabled = computed(() => props.menu.config.resizable === true)
const style = computed(() => ({
  left: position.value?.left || props.menu.config.position?.x || '50%',
  top: position.value?.top || props.menu.config.position?.y || '50%',
  width: resizeEnabled.value && dimensions.value?.width
    ? dimensions.value.width
    : (size.value.breakpoints ? 'var(--fm-responsive-width)' : (size.value.width || '32rem')),
  height: resizeEnabled.value && dimensions.value?.height ? dimensions.value.height : (size.value.height || 'auto'),
  minWidth: size.value.minWidth || '18rem',
  maxWidth: size.value.maxWidth || '90vw',
  minHeight: size.value.minHeight || 'auto',
  maxHeight: size.value.maxHeight || '85vh',
  resize: resizeEnabled.value ? 'both' : 'none',
  '--fm-accent': theme.value.accent || '#a73732',
  '--fm-bg': theme.value.background || 'rgba(22, 17, 14, .96)',
  '--fm-panel': theme.value.panel || 'rgba(255, 255, 255, .055)',
  '--fm-text': theme.value.text || '#f6eee3',
  '--fm-muted': theme.value.muted || '#c8b9a5',
  '--fm-radius': theme.value.radius || '8px',
  '--fm-font': theme.value.fontFamily || 'Georgia, serif',
  '--fm-width-720': size.value.breakpoints?.['720'] || size.value.width || '28rem',
  '--fm-width-1080': size.value.breakpoints?.['1080'] || size.value.width || '32rem',
  '--fm-width-1440': size.value.breakpoints?.['1440'] || size.value.width || '36rem',
  '--fm-width-2160': size.value.breakpoints?.['2160'] || size.value.width || '40rem',
}))

function close() { post('close', { menuId: props.menu.menuId }) }
function detectResize(event) {
  if (!resizeEnabled.value || event.button !== 0) return
  const rect = shell.value.getBoundingClientRect()
  resizing = event.clientX >= rect.right - 20 && event.clientY >= rect.bottom - 20
}
function startDrag(event) {
  if (props.menu.config.draggable === false || event.button !== 0) return
  dragging.value = true
  const rect = shell.value.getBoundingClientRect()
  dragOffset.x = event.clientX - rect.left; dragOffset.y = event.clientY - rect.top
  event.preventDefault()
}
function moveDrag(event) {
  if (!dragging.value) return
  const rect = shell.value.getBoundingClientRect()
  const left = Math.max(0, Math.min(window.innerWidth - rect.width, event.clientX - dragOffset.x))
  const top = Math.max(0, Math.min(window.innerHeight - Math.min(rect.height, 40), event.clientY - dragOffset.y))
  position.value = { left: `${left + rect.width / 2}px`, top: `${top + rect.height / 2}px` }
  if (props.menu.config.persistPosition !== false) localStorage.setItem(`feather-menu-v2:${props.menu.menuId}:position`, JSON.stringify(position.value))
}
function stopPointer() {
  dragging.value = false
  if (!resizing || !shell.value) { resizing = false; return }
  resizing = false
  const rect = shell.value.getBoundingClientRect()
  dimensions.value = { width: `${Math.round(rect.width)}px`, height: `${Math.round(rect.height)}px` }
  position.value = { left: `${Math.round(rect.left + rect.width / 2)}px`, top: `${Math.round(rect.top + rect.height / 2)}px` }
  if (props.menu.config.persistSize !== false) {
    localStorage.setItem(`feather-menu-v2:${props.menu.menuId}:size`, JSON.stringify(dimensions.value))
  }
  if (props.menu.config.persistPosition !== false) {
    localStorage.setItem(`feather-menu-v2:${props.menu.menuId}:position`, JSON.stringify(position.value))
  }
}
function keydown(event) {
  if (event.defaultPrevented) return
  if (event.key === 'Escape') { event.preventDefault(); close(); return }
  if (props.menu.keys?.[event.key]) { post('keyAction', { menuId: props.menu.menuId, key: event.key }); event.preventDefault(); return }
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return
  const controls = [...shell.value.querySelectorAll('[data-menu-control]:not([disabled])')]
  if (!controls.length) return
  const index = controls.indexOf(document.activeElement)
  const direction = event.key === 'ArrowDown' ? 1 : -1
  controls[(index + direction + controls.length) % controls.length].focus()
  event.preventDefault()
}

watch(() => [props.menu.revision, props.menu.activePageId], async () => { await nextTick() })
onMounted(() => {
  if (props.menu.config.persistPosition !== false) {
    try { position.value = JSON.parse(localStorage.getItem(`feather-menu-v2:${props.menu.menuId}:position`)) || undefined } catch { /* ignore invalid local state */ }
  }
  if (resizeEnabled.value && props.menu.config.persistSize !== false) {
    try { dimensions.value = JSON.parse(localStorage.getItem(`feather-menu-v2:${props.menu.menuId}:size`)) || undefined } catch { /* ignore invalid local state */ }
  }
  window.addEventListener('pointermove', moveDrag); window.addEventListener('pointerup', stopPointer)
  nextTick(() => shell.value?.querySelector('[data-menu-control]:not([disabled])')?.focus())
})
onUnmounted(() => { window.removeEventListener('pointermove', moveDrag); window.removeEventListener('pointerup', stopPointer) })
</script>

<template>
  <section ref="shell" class="menu-shell" :class="`theme-${theme.preset || 'redemption'}`" :style="style" @pointerdown.capture="detectResize" @keydown="keydown">
    <button v-if="menu.config.closable !== false" class="close" aria-label="Close menu" @click="close">×</button>
    <div class="drag-region" @pointerdown="startDrag">
      <ElementRenderer v-for="element in inSlot('header')" :key="element.elementId" :element="element" :menu="menu" :page="page" />
    </div>
    <NavigationBar v-if="menu.navigation" :menu="menu" />
    <main class="content">
      <ElementRenderer v-for="element in inSlot('content')" :key="element.elementId" :element="element" :menu="menu" :page="page" />
    </main>
    <footer>
      <ElementRenderer v-for="element in inSlot('footer')" :key="element.elementId" :element="element" :menu="menu" :page="page" />
    </footer>
  </section>
</template>
