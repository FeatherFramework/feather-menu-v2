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

  it('keeps Tab inside the menu and leaves text arrow keys alone', async () => {
    const value = menu()
    value.pages.selectors.elements.town = { elementId: 'town', type: 'input', data: { label: 'Text', value: 'draft' } }
    const wrapper = mount(MenuShell, { props: { menu: value }, attachTo: document.body })
    await nextTick()
    const input = wrapper.get('input'); input.element.focus()
    await input.trigger('keydown', { key: 'ArrowDown' })
    expect(document.activeElement).toBe(input.element)
    await input.trigger('keydown', { key: 'Tab' })
    expect(wrapper.element.contains(document.activeElement)).toBe(true)
    expect(document.activeElement).not.toBe(input.element)
    wrapper.unmount()
  })

  it('restores draft, focus and scroll across page navigation', async () => {
    const value = menu()
    value.pages.selectors.elements.town = { elementId: 'town', type: 'input', data: { label: 'Name', value: 'saved' } }
    value.pages.display = { pageId: 'display', elementOrder: ['other'], elements: { other: { elementId: 'other', type: 'button', data: { label: 'Other' } } } }
    const wrapper = mount(MenuShell, { props: { menu: value }, attachTo: document.body })
    await nextTick()
    const input = wrapper.get('input'); input.element.value = 'uncommitted'; await input.trigger('input'); input.element.focus()
    wrapper.get('.content').element.scrollTop = 120
    await wrapper.setProps({ menu: { ...value, activePageId: 'display' } }); await nextTick()
    expect(wrapper.find('input').exists()).toBe(false)
    await wrapper.setProps({ menu: { ...value, activePageId: 'selectors' } }); await nextTick()
    expect(wrapper.get('input').element.value).toBe('uncommitted')
    expect(document.activeElement).toBe(wrapper.get('input').element)
    expect(wrapper.get('.content').element.scrollTop).toBe(120)
    wrapper.unmount()
  })
})
