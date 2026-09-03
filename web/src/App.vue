<script setup>
import { computed } from 'vue'
import { state } from './store'
import MenuShell from './components/MenuShell.vue'

const menus = computed(() => Object.values(state.menus).filter((menu) => menu.open))
</script>

<template>
  <MenuShell v-for="menu in menus" :key="menu.menuId" :menu="menu" />
</template>

