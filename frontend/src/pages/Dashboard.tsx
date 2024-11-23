import { createSignal, onCleanup, createEffect, Show } from 'solid-js'
import { addRedirection, deleteRedirection, getRedirectionMapEntries, getModificationsAfterIndex, getRedirectionMapCount } from '../utils/fetch'
import { Table } from '../components/ui/table'
import { Pagination } from '../components/ui/pagination'
import { Button } from "../components/ui/button"
import { AlertDialog } from '../components/ui/alert-dialog'

import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle
} from "../components/ui/card"
import { TextField, TextFieldInput, TextFieldLabel } from "../components/ui/text-field"
import { Setter } from 'solid-js'


function AddRedirection() {
  const [error, setError] = createSignal<string | null>(null)
  const [success, setSuccess] = createSignal<string | null>(null)
  
  const [from, setFrom] = createSignal<string>('')
  const [to, setTo] = createSignal<string>('')
  const [lifetime, setLifetime] = createSignal<number>(3600)

  const handleSubmit = () => {
    setError(null)
    setSuccess(null)
    setFrom(prev => {
      if (!prev) return ''
      if (prev[0] == '/') prev = prev.slice(1)
      return prev
    })
    setTo(prev => {
      if (!prev) return ''
      if (!prev.startsWith('http') && !prev.includes('://')) prev = 'http://' + prev
      return prev
    })

    if (!from()) {
      setError('From location is required')
      return
    } else if (!to()) {
      setError('To location is required')
      return
    } else if (lifetime() <= 0) {
      setError('Lifetime must be positive')
      return
    }

    addRedirection(from(), to(), lifetime()).then(() => {
      setSuccess('Redirection added successfully!')
      setFrom('')
      setTo('')
      setLifetime(3600)
    }).catch(e => setError('Failed to add redirection: ' + e.message))
  }

  return (
    <Card class="w-[350px] m-auto">
      <CardHeader>
        <CardTitle class="text-center">Add Redirection</CardTitle>
        <Show when={error()} fallback={
          <CardDescription class="text-center">
            {success() ? success() : 'Add a redirection'}
          </CardDescription>
        }>
          <CardDescription class="text-center text-red-500">
            {error()}
          </CardDescription>
        </Show>
      </CardHeader>
      <CardContent class="space-y-2">
        {/* From Location Input */}
        <TextField class="space-y-1">
          <TextFieldLabel>From</TextFieldLabel>
          <TextFieldInput
            placeholder="eg. /google"
            type="text"
            value={from()}
            onInput={(e) => setFrom(e.target.nodeValue ?? '') }
          />
        </TextField>
        
        {/* To Location Input */}
        <TextField class="space-y-1">
          <TextFieldLabel>To</TextFieldLabel>
          <TextFieldInput
            placeholder="https://google.com"
            type="text"
            value={to()}
            onInput={(e) => setTo(e.target.nodeValue ?? '')}
          />
        </TextField>

        {/* Lifetime Input */}
        <TextField class="space-y-1">
          <TextFieldLabel>Lifetime (Seconds)</TextFieldLabel>
          <TextFieldInput
            placeholder="Enter lifetime in seconds"
            type="number"
            value={lifetime()}
            onInput={(e) => setLifetime(Number(e.target.nodeValue ?? '0'))}
          />
        </TextField>
      </CardContent>
      <CardFooter class="justify-center">
        <Button onClick={handleSubmit}>
          Add Redirection
        </Button>
      </CardFooter>
    </Card>
  )
}

export default function Dashboard({sP}: {sP: Setter<string>}) {
  //const [redirections, setRedirections] = createSignal([])
  //const [modifications, setModifications] = createSignal([])
  //const [loading, setLoading] = createSignal(false)
  //const [page, setPage] = createSignal(0)
  //const [count, setCount] = createSignal(10)
  //
  //const [error, setError] = createSignal<string>('')
  //
  //async function fetchRedirections(from: number, count: number) {
  //  setLoading(true)
  //  try {
  //    const { entries } = await getRedirectionMapEntries(from, count)
  //    return entries
  //  } catch (e: unknown) {
  //    setError((e as Error).message)
  //  }
  //  setLoading(false)
  //  return undefined
  //}
  //
  //async function applyModifications() {
  //  try {
  //    const { entries } = await getModificationsAfterIndex(0)
  //    return entries
  //  } catch (e: unknown) {
  //    setError((e as Error).message)
  //  }
  //  return undefined
  //}
  //
  //const handleAddRedirection = async (from: string, to: string, lifetime: number) => {
  //  setLoading(true)
  //  try {
  //    await addRedirection(from, to, lifetime)
  //    alert('Redirection added')
  //  } catch (error) {
  //    alert('Error adding redirection')
  //  } finally {
  //    setLoading(false)
  //  }
  //}
  //
  //
  //const handleDeleteRedirection = async (from: string) => {
  //  setLoading(true)
  //  try {
  //    await deleteRedirection(from)
  //    alert('Redirection deleted')
  //  } catch (error) {
  //    alert('Error deleting redirection')
  //  } finally {
  //    setLoading(false)
  //  }
  //}
  //
  //createEffect(() => {
  //  fetchRedirections(0, 1024).then(setRedirections).catch(e => setError(e.message))
  //})

  return (
    <div>
      <h1>Redirection Dashboard</h1>
      <AddRedirection />
    </div>
  )
}

