<script setup>
import { computed, nextTick, onMounted, onUnmounted, provide, ref, watch } from 'vue'
import ElementRenderer from './elements/ElementRenderer.vue'
import NavigationBar from './NavigationBar.vue'
import { post } from '../api'
import { controls, startGamepad } from '../input'

const props = defineProps({ menu: { type: Object, required: true } })
const shell = ref(null)
const busyActions = ref(new Set())
const showBusy = ref(false)
let busyTimer
provide('menuBusy', (key, busy) => {
  if (busy) busyActions.value.add(key)
  else busyActions.value.delete(key)
})
watch(() => busyActions.value.size > 0, (busy) => {
  clearTimeout(busyTimer)
  if (!busy) showBusy.value = false
  else busyTimer = setTimeout(() => { showBusy.value = true }, 250)
})
const confirmation = ref(null)
const confirmPanel = ref(null)
let confirmResolve, confirmFocus
function finishConfirmation(accepted) {
  const resolve = confirmResolve
  confirmResolve = null
  confirmation.value = null
  resolve?.(accepted)
  nextTick(() => { if (confirmFocus?.isConnected) confirmFocus.focus() })
}
provide('menuConfirm', async (spec) => {
  if (confirmation.value) return false
  confirmFocus = document.activeElement
  confirmation.value = spec
  const result = new Promise((resolve) => { confirmResolve = resolve })
  await nextTick()
  confirmPanel.value?.querySelector('[data-menu-control]')?.focus()
  return result
})
function confirmationKey(event) {
  if (event.key === 'Escape') { event.preventDefault(); finishConfirmation(false); return }
  if (['Tab', 'ArrowUp', 'ArrowDown'].includes(event.key)) {
    const available = controls(confirmPanel.value)
    const direction = event.shiftKey || event.key === 'ArrowUp' ? -1 : 1
    available[(available.indexOf(document.activeElement) + direction + available.length) % available.length]?.focus()
    event.preventDefault()
  }
}
const pageUi = { drafts: new Map(), pages: new Map() }
const openSections = ref({})
provide('menuPageUi', pageUi)
const dragging = ref(false)
const position = ref()
const dimensions = ref()
const dragOffset = { x: 0, y: 0 }
let resizing = false
let stopGamepad

const page = computed(() => props.menu.pages[props.menu.activePageId])
const elements = computed(() => page.value?.elementOrder.map((id) => page.value.elements[id]).filter(Boolean) || [])
const inSlot = (slot) => elements.value.filter((element) => (element.data.slot || 'content') === slot)
function groupedSlot(slot) {
  const groups = []
  for (const element of inSlot(slot)) {
    const row = element.data.row
    const previous = groups[groups.length - 1]
    if (row && previous?.row === row) previous.elements.push(element)
    else groups.push({ key: row ? `${row}:${element.elementId}` : element.elementId, row, elements: [element] })
  }
  return groups
}
function contentGroups() {
  const groups = []
  const sections = new Map()
  for (const element of inSlot('content')) {
    if (element.type === 'accordion') {
      const group = { key: element.elementId, accordion: element, children: [] }
      groups.push(group)
      sections.set(element.key || element.data.key, group)
      continue
    }
    const target = sections.get(element.data.section)?.children || groups
    const row = element.data.row
    const previous = target[target.length - 1]
    if (row && previous?.row === row) previous.elements.push(element)
    else target.push({ key: row ? `${row}:${element.elementId}` : element.elementId, row, elements: [element] })
  }
  return groups
}
function sectionOpen(element) {
  const key = `${props.menu.activePageId}/${element.elementId}`
  return openSections.value[key] ?? element.data.value === true
}
async function toggleSection(element) {
  const key = `${props.menu.activePageId}/${element.elementId}`
  const value = !sectionOpen(element)
  openSections.value[key] = value
  if (element.data.notify === true) {
    const result = await post('elementAction', { menuId: props.menu.menuId, pageId: props.menu.activePageId, elementId: element.elementId, event: 'change', value })
    if (result?.ok === false) openSections.value[key] = element.data.value === true
  }
}
const theme = computed(() => props.menu.config.theme || {})
const size = computed(() => props.menu.config.size || {})
const resizeEnabled = computed(() => props.menu.config.resizable === true)
const left = computed(() => position.value?.left || props.menu.config.position?.x || '50%')
const top = computed(() => position.value?.top || props.menu.config.position?.y || '50%')
const topLeftAnchored = computed(() => (position.value?.anchor || props.menu.config.position?.anchor) === 'top-left')
const style = computed(() => ({
  left: left.value,
  top: top.value,
  transform: topLeftAnchored.value ? 'none' : 'translate(-50%, -50%)',
  width: resizeEnabled.value && dimensions.value?.width
    ? dimensions.value.width
    : (size.value.breakpoints ? 'var(--fm-responsive-width)' : (size.value.width || '32rem')),
  height: resizeEnabled.value && dimensions.value?.height ? dimensions.value.height : (size.value.height || 'auto'),
  minWidth: size.value.minWidth || '18rem',
  maxWidth: topLeftAnchored.value
    ? `min(${size.value.maxWidth || '90vw'}, calc(100vw - ${left.value}))`
    : (size.value.maxWidth || '90vw'),
  minHeight: size.value.minHeight || 'auto',
  maxHeight: topLeftAnchored.value
    ? `min(${size.value.maxHeight || '85vh'}, calc(100vh - ${top.value}))`
    : (size.value.maxHeight || '85vh'),
  resize: resizeEnabled.value ? 'both' : 'none',
  '--fm-accent': theme.value.accent || '#a73732',
  '--fm-bg': theme.value.background || 'rgba(22, 17, 14, .96)',
  '--fm-panel': theme.value.panel || 'rgba(255, 255, 255, .055)',
  '--fm-text': theme.value.text || '#f6eee3',
  '--fm-muted': theme.value.muted || '#c8b9a5',
  '--fm-radius': theme.value.radius || '8px',
  '--fm-font': theme.value.fontFamily === 'rdr' ? 'RDRLino, Georgia, serif' : (theme.value.fontFamily || 'RDRLino, Georgia, serif'),
  '--fm-width-720': size.value.breakpoints?.['720'] || size.value.width || '28rem',
  '--fm-width-1080': size.value.breakpoints?.['1080'] || size.value.width || '32rem',
  '--fm-width-1440': size.value.breakpoints?.['1440'] || size.value.width || '36rem',
  '--fm-width-2160': size.value.breakpoints?.['2160'] || size.value.width || '40rem',
}))

function close() { post('close', { menuId: props.menu.menuId }) }
function persistPosition() {
  if (props.menu.config.persistPosition !== false) {
    localStorage.setItem(`feather-menu-v2:${props.menu.menuId}:position`, JSON.stringify(position.value))
  }
}
function normalizePosition() {
  if (!shell.value || topLeftAnchored.value) return
  const rect = shell.value.getBoundingClientRect()
  position.value = {
    left: `${Math.round(Math.max(0, Math.min(window.innerWidth - rect.width, rect.left)))}px`,
    top: `${Math.round(Math.max(0, Math.min(window.innerHeight - Math.min(rect.height, 40), rect.top)))}px`,
    anchor: 'top-left',
  }
  persistPosition()
}
function rememberFocus(event) {
  const anchor = event.target.closest('[data-element-id]')
  if (!anchor) return
  pageUi.pages.set(props.menu.activePageId, {
    ...pageUi.pages.get(props.menu.activePageId),
    elementId: anchor.dataset.elementId,
    controlIndex: [...anchor.querySelectorAll('[data-menu-control]')].indexOf(event.target),
  })
}
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
  position.value = { left: `${left}px`, top: `${top}px`, anchor: 'top-left' }
  persistPosition()
}
function stopPointer() {
  dragging.value = false
  if (!resizing || !shell.value) { resizing = false; return }
  resizing = false
  const rect = shell.value.getBoundingClientRect()
  dimensions.value = { width: `${Math.round(rect.width)}px`, height: `${Math.round(rect.height)}px` }
  position.value = { left: `${Math.round(rect.left)}px`, top: `${Math.round(rect.top)}px`, anchor: 'top-left' }
  if (props.menu.config.persistSize !== false) {
    localStorage.setItem(`feather-menu-v2:${props.menu.menuId}:size`, JSON.stringify(dimensions.value))
  }
  persistPosition()
}
function keydown(event) {
  if (event.defaultPrevented) return
  if (event.key === 'Escape') { event.preventDefault(); close(); return }
  if (event.key === 'Tab') {
    const available = controls(shell.value)
    const direction = event.shiftKey ? -1 : 1
    available[(available.indexOf(document.activeElement) + direction + available.length) % available.length]?.focus()
    event.preventDefault(); return
  }
  if (event.target.matches('input, textarea')) return
  if (props.menu.keys?.[event.key]) { post('keyAction', { menuId: props.menu.menuId, key: event.key }); event.preventDefault(); return }
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return
  const available = controls(shell.value)
  if (!available.length) return
  const index = available.indexOf(document.activeElement)
  const direction = event.key === 'ArrowDown' ? 1 : -1
  available[(index + direction + available.length) % available.length].focus()
  event.preventDefault()
}

watch(() => props.menu.activePageId, async (pageId, previousPageId) => {
  if (confirmation.value) finishConfirmation(false)
  if (previousPageId && shell.value) {
    pageUi.pages.set(previousPageId, {
      ...pageUi.pages.get(previousPageId),
      scroll: shell.value.querySelector('.content')?.scrollTop || 0,
    })
  }
  await nextTick()
  if (!shell.value) return
  const saved = pageUi.pages.get(pageId)
  const content = shell.value.querySelector('.content')
  if (content) content.scrollTop = saved?.scroll || 0
  const anchor = saved?.elementId && [...shell.value.querySelectorAll('[data-element-id]')].find((node) => node.dataset.elementId === saved.elementId)
  const remembered = anchor?.querySelectorAll('[data-menu-control]')[saved?.controlIndex || 0]
  const target = (remembered && !remembered.matches(':disabled') && !remembered.closest('[hidden]') && remembered) || [...(anchor?.querySelectorAll('[data-menu-control]:not(:disabled)') || [])].find((node) => !node.closest('[hidden]')) || controls(shell.value).find((node) => node.closest('.content')) || shell.value.querySelector('.stepper-next:not(:disabled), .navigation .active:not(:disabled)') || controls(shell.value)[0]
  target?.focus({ preventScroll: true })
})
watch(() => props.menu.revision, async () => {
  await nextTick()
  for (const [key, draft] of pageUi.drafts) if (!props.menu.pages[draft.pageId]?.elements[draft.elementId]) pageUi.drafts.delete(key)
  for (const id of pageUi.pages.keys()) if (!props.menu.pages[id]) pageUi.pages.delete(id)
})
onMounted(() => {
  stopGamepad = startGamepad(() => props.menu.config.controller === false ? null : (confirmation.value ? confirmPanel.value : shell.value))
  if (props.menu.config.persistPosition !== false) {
    try { position.value = JSON.parse(localStorage.getItem(`feather-menu-v2:${props.menu.menuId}:position`)) || undefined } catch { /* ignore invalid local state */ }
  }
  if (resizeEnabled.value && props.menu.config.persistSize !== false) {
    try { dimensions.value = JSON.parse(localStorage.getItem(`feather-menu-v2:${props.menu.menuId}:size`)) || undefined } catch { /* ignore invalid local state */ }
  }
  window.addEventListener('pointermove', moveDrag); window.addEventListener('pointerup', stopPointer)
  nextTick(() => {
    normalizePosition()
    shell.value?.querySelector('[data-menu-control]:not([disabled])')?.focus()
  })
})
onUnmounted(() => { clearTimeout(busyTimer); finishConfirmation(false); stopGamepad?.(); window.removeEventListener('pointermove', moveDrag); window.removeEventListener('pointerup', stopPointer) })
</script>

<template>
  <section ref="shell" :inert="confirmation ? true : undefined" class="menu-shell" role="dialog" aria-label="Menu" aria-modal="true" :class="`theme-${theme.preset || 'redemption'}`" :style="style" @focusin="rememberFocus" @pointerdown.capture="detectResize" @keydown="keydown">
    <span v-if="showBusy" class="menu-busy" :class="{ 'without-close': menu.config.closable === false }" role="status" aria-busy="true"><span class="busy-indicator" aria-hidden="true" /></span>
    <button v-if="menu.config.closable !== false" class="close" aria-label="Close menu" @click="close">×</button>
    <div class="drag-region" @pointerdown="startDrag">
      <template v-for="group in groupedSlot('header')" :key="group.key">
        <div v-if="group.row" class="element-row" :style="{ '--row-columns': group.elements.length }">
          <ElementRenderer v-for="element in group.elements" :key="element.elementId" :element="element" :menu="menu" :page="page" />
        </div>
        <ElementRenderer v-else :element="group.elements[0]" :menu="menu" :page="page" />
      </template>
    </div>
    <NavigationBar v-if="menu.navigation" :menu="menu" />
    <main class="content">
      <template v-for="group in contentGroups()" :key="group.key">
        <section v-if="group.accordion" class="accordion" :data-element-id="group.accordion.elementId">
          <button class="accordion-trigger" :class="{ 'label-centered': group.accordion.data.labelAlign === 'center' }" type="button" data-menu-control :disabled="group.accordion.data.disabled" :aria-current="group.accordion.data.selected ? 'true' : undefined" :aria-expanded="sectionOpen(group.accordion)" :aria-controls="`accordion-${group.accordion.elementId}`" @click="toggleSection(group.accordion)">
            <span><span v-if="group.accordion.data.selected" class="selection-marker" aria-hidden="true">&lt;</span>{{ group.accordion.data.label }}<span v-if="group.accordion.data.selected" class="selection-marker" aria-hidden="true">&gt;</span></span>
            <span aria-hidden="true">{{ sectionOpen(group.accordion) ? '▾' : '▸' }}</span>
          </button>
          <div :id="`accordion-${group.accordion.elementId}`" class="accordion-panel" :hidden="!sectionOpen(group.accordion)">
            <template v-for="child in group.children" :key="child.key">
              <div v-if="child.row" class="element-row" :style="{ '--row-columns': child.elements.length }">
                <ElementRenderer v-for="element in child.elements" :key="element.elementId" :element="element" :menu="menu" :page="page" />
              </div>
              <ElementRenderer v-else :element="child.elements[0]" :menu="menu" :page="page" />
            </template>
          </div>
        </section>
        <div v-else-if="group.row" class="element-row" :style="{ '--row-columns': group.elements.length }">
          <ElementRenderer v-for="element in group.elements" :key="element.elementId" :element="element" :menu="menu" :page="page" />
        </div>
        <ElementRenderer v-else :element="group.elements[0]" :menu="menu" :page="page" />
      </template>
    </main>
    <footer>
      <template v-for="group in groupedSlot('footer')" :key="group.key">
        <div v-if="group.row" class="element-row" :style="{ '--row-columns': group.elements.length }">
          <ElementRenderer v-for="element in group.elements" :key="element.elementId" :element="element" :menu="menu" :page="page" />
        </div>
        <ElementRenderer v-else :element="group.elements[0]" :menu="menu" :page="page" />
      </template>
    </footer>
  <Teleport to="#overlay-root">
    <div v-if="confirmation" class="confirmation-backdrop">
      <section ref="confirmPanel" class="confirmation-dialog" role="alertdialog" aria-modal="true" :aria-labelledby="`${menu.menuId}-confirm-title`" :aria-describedby="`${menu.menuId}-confirm-message`" :style="style" @keydown.stop="confirmationKey">
        <h2 :id="`${menu.menuId}-confirm-title`">{{ confirmation.title }}</h2>
        <p :id="`${menu.menuId}-confirm-message`">{{ confirmation.message }}</p>
        <div class="element-row" style="--row-columns: 2">
          <button class="control button" data-menu-control @click="finishConfirmation(false)">{{ confirmation.cancelLabel }}</button>
          <button class="control button" data-menu-control @click="finishConfirmation(true)">{{ confirmation.confirmLabel }}</button>
        </div>
      </section>
    </div>
  </Teleport>
  </section>
</template>
