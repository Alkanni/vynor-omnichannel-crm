import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import aiAgents from 'dashboard/i18n/locale/en/aiAgents.json';
import BookingFieldsEditor from '../BookingFieldsEditor.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: aiAgents },
});

const TagInputStub = {
  name: 'TagInput',
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template: '<div />',
};

const field = (name, changes = {}) => ({
  name,
  description: '',
  type: 'text',
  options: [],
  required: false,
  ...changes,
});

const mountEditor = fields => {
  const wrapper = mount(BookingFieldsEditor, {
    props: {
      modelValue: fields,
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
    global: { plugins: [i18n], stubs: { TagInput: TagInputStub } },
  });
  return wrapper;
};

const fields = wrapper => wrapper.props('modelValue');

const button = (wrapper, label, row = 0) =>
  wrapper.findAll(`button[aria-label="${label}"]`)[row];

const addButton = wrapper =>
  wrapper.findAll('button').find(element => element.text() === 'Add field');

describe('BookingFieldsEditor', () => {
  it('adds a text field and edits its name, description, and requirement', async () => {
    const wrapper = mountEditor([]);

    await addButton(wrapper).trigger('click');
    const [name, description] = wrapper.findAll('input:not([type=checkbox])');
    await name.setValue('Plat nomor');
    await description.setValue('Contoh: D 1234 ABC');
    await wrapper.find('input[type=checkbox]').setValue(true);

    expect(fields(wrapper)).toEqual([
      field('Plat nomor', {
        description: 'Contoh: D 1234 ABC',
        required: true,
      }),
    ]);
    expect(description.attributes('maxlength')).toBe('200');
  });

  it('asks for options only for a choice, and clears them for another type', async () => {
    const wrapper = mountEditor([field('Mobil')]);
    expect(wrapper.findComponent(TagInputStub).exists()).toBe(false);

    await wrapper.find('select').setValue('choice');
    wrapper
      .findComponent(TagInputStub)
      .vm.$emit('update:modelValue', ['Avanza', 'Xenia']);
    await wrapper.vm.$nextTick();
    expect(fields(wrapper)).toEqual([
      field('Mobil', { type: 'choice', options: ['Avanza', 'Xenia'] }),
    ]);

    await wrapper.find('select').setValue('number');
    expect(fields(wrapper)).toEqual([field('Mobil', { type: 'number' })]);
    expect(wrapper.findComponent(TagInputStub).exists()).toBe(false);
  });

  it('moves and removes fields, without moving the first up or the last down', async () => {
    const wrapper = mountEditor([field('A'), field('B'), field('C')]);

    expect(button(wrapper, 'Move up', 0).attributes('disabled')).toBeDefined();
    expect(
      button(wrapper, 'Move down', 2).attributes('disabled')
    ).toBeDefined();

    await button(wrapper, 'Move down', 0).trigger('click');
    expect(fields(wrapper).map(({ name }) => name)).toEqual(['B', 'A', 'C']);

    await button(wrapper, 'Move up', 2).trigger('click');
    expect(fields(wrapper).map(({ name }) => name)).toEqual(['B', 'C', 'A']);

    await button(wrapper, 'Remove field', 1).trigger('click');
    expect(fields(wrapper).map(({ name }) => name)).toEqual(['B', 'A']);
  });

  it('adds no more than 10 fields', () => {
    const wrapper = mountEditor(
      Array.from({ length: 10 }, (_, index) => field(`Field ${index}`))
    );

    expect(addButton(wrapper).attributes('disabled')).toBeDefined();
  });
});
