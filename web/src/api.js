const resourceName = typeof globalThis.GetParentResourceName === 'function'
  ? globalThis.GetParentResourceName()
  : 'feather-menu-v2'

export async function post(endpoint, payload = {}) {
  if (typeof globalThis.GetParentResourceName !== 'function') return { ok: true }
  const response = await fetch(`https://${resourceName}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload),
  })
  return response.json()
}
