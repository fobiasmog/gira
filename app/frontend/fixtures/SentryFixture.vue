<script setup lang="ts">
import { defineComponent, h, ref } from "vue"
import { defineStore } from "pinia"
import { identifyUser } from "../sentry/index.ts"

// Test-only page (built with --mode test): a component showing a task throws,
// with the task's text in a store, in the component's props, in a request body
// and in the console, so the system test can check none of it is reported.
const TASK = { title: "Top secret title", description: "Secret description", assignee: "secret@example.com" }

const useTaskStore = defineStore("fixture-task", () => {
  const task = ref<typeof TASK | null>(null)
  function show() { task.value = { ...TASK } }
  return { task, show }
})

const TaskView = defineComponent({
  props: { title: { type: String, required: true }, description: { type: String, required: true } },
  setup(props) {
    return () => {
      throw new Error(`TaskView failed to render (${props.title.length} characters)`)
    }
  },
})

const store = useTaskStore()
const showing = ref(false)
identifyUser(Number(new URLSearchParams(location.search).get("user_id")))

async function show() {
  store.show()
  console.log("Showing a task for", TASK.assignee)
  await fetch("/api/fixture-echo", { method: "POST", body: JSON.stringify(TASK) }).catch(() => {})
  showing.value = true
}

const TaskSlot = () => (showing.value ? h(TaskView, { title: TASK.title, description: TASK.description }) : null)
</script>

<template>
  <main class="stack">
    <h1>Error reporting fixture</h1>
    <button type="button" class="button" @click="show">Show the task</button>
    <TaskSlot />
  </main>
</template>
