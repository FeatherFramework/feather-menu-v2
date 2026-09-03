import { post } from './api'
import { handleMessage } from './store'

const pendingResync = new Set()

export function processMessage(data = {}) {
  const applied = handleMessage(data)
  if (data.action === 'menu:sync' && applied) pendingResync.delete(data.menu?.menuId)
  if (data.action === 'menu:destroy') pendingResync.delete(data.menuId)
  if (data.action === 'menu:patch' && !applied && typeof data.menuId === 'string' && !pendingResync.has(data.menuId)) {
    pendingResync.add(data.menuId)
    post('desync', { menuId: data.menuId })
  }
  return applied
}

export function resetMessageRecovery() {
  pendingResync.clear()
}
