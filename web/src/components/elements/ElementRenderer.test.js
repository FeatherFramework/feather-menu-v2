import { beforeEach, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import ElementRenderer from './ElementRenderer.vue'
import { post } from '../../api'

vi.mock('../../api', () => ({ post: vi.fn(() => Promise.resolve({ ok: true })) }))

const mountElement = (type, data, elementId = type) => mount(ElementRenderer, {
  props: {
    element: { elementId, type, data },
    menu: { menuId: 'owner:menu', config: {} },
    page: { pageId: 'page' },
  },
})

describe('ElementRenderer interactions', () => {
  beforeEach(() => vi.clearAllMocks())

  it('emits an activation from a button', async () => {
    const wrapper = mountElement('button', { label: 'Save', value: 'save' })
    await wrapper.get('button').trigger('click')
    expect(post).toHaveBeenCalledWith('elementAction', {
      menuId: 'owner:menu', pageId: 'page', elementId: 'button', event: 'activate', value: 'save', meta: undefined,
    })
  })

  it('toggles from its local controlled value', async () => {
    const wrapper = mountElement('toggle', { label: 'Enabled', value: false })
    await wrapper.get('button').trigger('click')
    expect(wrapper.get('button').attributes('aria-checked')).toBe('true')
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({ event: 'change', value: true }))
  })

  it('emits page-arrow intent without changing the controlled readout', async () => {
    const wrapper = mountElement('pagearrows', { current: 2, total: 5 })
    await wrapper.findAll('button')[1].trigger('click')
    expect(wrapper.text()).toContain('2/5')
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({ event: 'next', value: 1 }))
  })

  it('tracks a grid drag locally and commits only on pointer release', async () => {
    const wrapper = mountElement('gridslider', { label: 'Face', value: { x: 1, y: 1 }, maxx: 10, maxy: 10 })
    const grid = wrapper.get('.grid-slider')
    grid.element.getBoundingClientRect = () => ({ left: 0, top: 0, width: 100, height: 100 })
    await grid.trigger('pointerdown', { button: 0, pointerId: 7, clientX: 20, clientY: 30 })
    await grid.trigger('pointermove', { pointerId: 7, clientX: 50, clientY: 60 })
    expect(post).not.toHaveBeenCalled()
    await grid.trigger('pointerup', { pointerId: 7, clientX: 50, clientY: 60 })
    expect(post).toHaveBeenCalledTimes(1)
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({ event: 'change', value: { x: 5, y: 6 } }))
  })

  it('supports bounded keyboard steps on the grid slider', async () => {
    const wrapper = mountElement('gridslider', { label: 'Face', value: { x: 1, y: 1 }, maxx: 2, maxy: 2, step: 0.25 })
    const grid = wrapper.get('.grid-slider')
    await grid.trigger('keydown', { key: 'ArrowRight' })
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({ value: { x: 1.25, y: 1 } }))
    await grid.trigger('keydown', { key: 'ArrowUp' })
    expect(post).toHaveBeenLastCalledWith('elementAction', expect.objectContaining({ value: { x: 1.25, y: 0.75 } }))
  })

  it('disables page arrows at their controlled boundaries', () => {
    const first = mountElement('pagearrows', { current: 1, total: 5 })
    expect(first.findAll('button')[0].attributes('disabled')).toBeDefined()
    expect(first.findAll('button')[1].attributes('disabled')).toBeUndefined()
    const last = mountElement('pagearrows', { current: 5, total: 5 })
    expect(last.findAll('button')[1].attributes('disabled')).toBeDefined()
  })

  it.each([
    ['header', { value: 'Heading' }, 'h1'],
    ['subheader', { value: 'Subheading' }, 'h2'],
    ['textdisplay', { value: 'Read only' }, 'p'],
    ['line', {}, 'hr'],
    ['spacer', { size: 'large' }, '.spacer-large'],
  ])('renders the static %s element', (type, data, selector) => {
    expect(mountElement(type, data).find(selector).exists()).toBe(true)
  })

  it('commits text and numeric fields on change', async () => {
    const text = mountElement('input', { label: 'Name', value: 'Arthur' })
    await text.get('input').setValue('John')
    await text.get('input').trigger('change')
    expect(post).toHaveBeenLastCalledWith('elementAction', expect.objectContaining({ value: 'John' }))
    const number = mountElement('number', { label: 'Age', value: 36, min: 18, max: 99, step: 1 })
    await number.get('input').setValue(40)
    await number.get('input').trigger('change')
    expect(post).toHaveBeenLastCalledWith('elementAction', expect.objectContaining({ value: 40 }))
  })

  it('wraps an arrow selector through scalar option values', async () => {
    const wrapper = mountElement('arrows', { value: 'sunny', options: [
      { value: 'sunny', label: 'Sunny' }, { value: 'rain', label: 'Rain' },
    ] })
    await wrapper.findAll('button')[0].trigger('click')
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({ value: 'rain' }))
  })

  it('selects radio and palette values', async () => {
    const radio = mountElement('radio', { label: 'Camp', value: 'quiet', options: [
      { value: 'quiet', label: 'Quiet' }, { value: 'social', label: 'Social' },
    ] })
    await radio.findAll('input')[1].setValue(true)
    expect(post).toHaveBeenLastCalledWith('elementAction', expect.objectContaining({ value: 'social' }))
    const palette = mountElement('colorpicker', { label: 'Color', value: '#a00', options: [
      { value: '#a00', label: 'Red' }, { value: '#00a', label: 'Blue' },
    ] })
    await palette.findAll('button')[1].trigger('click')
    expect(post).toHaveBeenLastCalledWith('elementAction', expect.objectContaining({ value: '#00a' }))
  })

  it('clamps read-only progress presentation', () => {
    const wrapper = mountElement('progress', { label: 'Load', value: 150, min: 0, max: 100 })
    expect(wrapper.get('[role="progressbar"] i').attributes('style')).toContain('100%')
  })

  it('emits the selected image-container child', async () => {
    const wrapper = mountElement('imageboxcontainer', { items: [
      { key: 'one', value: 'one', label: 'First', image: 'one.png' },
      { key: 'two', value: 'two', label: 'Second', image: 'two.png' },
    ] })
    await wrapper.findAll('button')[1].trigger('click')
    expect(post).toHaveBeenCalledWith('elementAction', expect.objectContaining({
      event: 'child', value: 'two', meta: { child: expect.objectContaining({ key: 'two' }) },
    }))
  })

  it('does not activate a disabled button', async () => {
    const wrapper = mountElement('button', { label: 'Disabled', disabled: true })
    await wrapper.get('button').trigger('click')
    expect(post).not.toHaveBeenCalled()
  })

  it('reacts to an external controlled-value update', async () => {
    const wrapper = mountElement('toggle', { label: 'Enabled', value: false })
    await wrapper.setProps({ element: { elementId: 'toggle', type: 'toggle', data: { label: 'Enabled', value: true } } })
    expect(wrapper.get('button').attributes('aria-checked')).toBe('true')
  })
})
