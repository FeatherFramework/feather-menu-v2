import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { nextTick } from 'vue'
import MenuShell from './MenuShell.vue'
import { post } from '../api'

vi.mock('../api', () => ({ post: vi.fn(() => Promise.resolve({ ok: true })) }))

const menu = () => ({
  menuId: 'owner:menu', revision: 1, activePageId: 'selectors', keys: {},
  config: { closable: true, draggable: true, persistPosition: false },
  navigation: {
    type: 'tabs', pages: [
      { pageId: 'display', label: 'Display' },
      { pageId: 'selectors', label: 'Selectors' },
    ],
  },
  pages: {
    selectors: {
      pageId: 'selectors', elementOrder: ['town'],
      elements: {
        town: {
          elementId: 'town', type: 'dropdown', data: {
            label: 'Town', value: 'valentine', options: [
              { label: 'Valentine', value: 'valentine' },
              { label: 'Locked', value: 'locked', disabled: true },
              { label: 'Blackwater', value: 'blackwater' },
            ],
          },
        },
      },
    },
  },
})

describe('MenuShell keyboard ownership', () => {
  beforeEach(() => {
    document.body.innerHTML = '<div id="overlay-root"></div>'
    vi.clearAllMocks()
  })
  afterEach(() => { document.body.innerHTML = '' })

  it('lets an open dropdown own arrows and Escape', async () => {
    const wrapper = mount(MenuShell, { props: { menu: menu() }, attachTo: document.body })
    await nextTick()
    const dropdown = wrapper.get('[role="combobox"]')
    dropdown.element.focus()
    await dropdown.trigger('keydown', { key: 'ArrowDown' })
    await dropdown.trigger('keydown', { key: 'ArrowDown' })
    expect(document.activeElement).toBe(dropdown.element)
    expect(document.querySelector('#overlay-root .active')?.textContent).toContain('Blackwater')

    await dropdown.trigger('keydown', { key: 'Escape' })
    expect(document.querySelector('#overlay-root [role="listbox"]')).toBeNull()
    expect(post).not.toHaveBeenCalledWith('close', expect.anything())
    wrapper.unmount()
  })
})
