import { createApp } from 'vue'
import App from './App.vue'
import './styles.css'
import { processMessage } from './messageHandler'
import { post } from './api'

window.addEventListener('message', (event) => {
  processMessage(event.data || {})
  if (event.data?.action === 'element:focus') {
    document.querySelector(`[data-element-id="${CSS.escape(event.data.elementId)}"] [data-menu-control]`)?.focus()
  }
})

createApp(App).mount('#app')
if (typeof globalThis.GetParentResourceName === 'function') post('ready')
else if (import.meta.env.DEV) import('./devFixture').then(({ loadDevelopmentFixture }) => loadDevelopmentFixture())
