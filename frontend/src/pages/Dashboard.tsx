import { createSignal, onCleanup, createEffect, Show, createResource, For, indexArray } from 'solid-js'
import { addRedirection, deleteRedirection, getRedirectionMapEntries, getModificationsAfterIndex, getRedirectionMapCount, site, ModificationType } from '../utils/fetch'
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
import { cn } from '../lib/utils'
import { Badge } from '../components/ui/badge'
import { IconArrowRight, IconExternalLink, IconMinus, IconPlus } from '../components/icons'


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
      if (prev.startsWith(site)) {
        prev = prev.slice(site.length)
      } else if (prev[0] == '/') {
        prev = prev.slice(1)
      }

      if (prev.startsWith('http')) throw new Error('Invalid from, location must not include the domain')
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
            placeholder="/google"
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

function ShowHistory() {
  const [history] = createResource(0, getModificationsAfterIndex)
  createEffect(() => {
    console.log(history())
  })
  return (
    <Show when={history()} fallback={
      history()?.entries?.length === 0 ?
        <div class="flex h-[600px] flex-col gap-2 overflow-auto p-4 pt-0">
          <div class="flex flex-col items-center justify-center gap-2 text-center">
            <div class="text-xl font-bold">No history found</div>
            <div class="text-sm text-muted-foreground">
              You haven't made any changes to the site yet
            </div>
          </div>
        </div>:
        <div class="flex h-[600px] flex-col gap-2 overflow-auto p-4 pt-0">
          <div class="flex flex-col items-center justify-center gap-2 text-center">
            <div class="text-xl font-bold">Loading history...</div>
            <div class="text-sm text-muted-foreground">
              Please wait while we load the history
            </div>
          </div>
        </div>
    }>
      <div class="flex flex-col overflow-auto p-4">
        <For each={history()!.entries}>
          {(item) => (
            <button
              type="button"
              class="flex flex-col items-start gap-2 rounded-lg border p-3 text-left text-sm transition-all"
            >
              <div class="flex w-full flex-col gap-1">
                <div class="flex items-center">
                  {item.modificationType === ModificationType.CREATED?
                    <IconPlus class="rounded-full mr-2 bg-green-700" />:
                    <IconMinus class="rounded-full mr-2 bg-red-700" />
                  }
                  <div class="items-center gap-2 flex p-2 rounded-full hover:bg-accent" onclick={() => window.open(site + item.modification.location, '_blank')}>
                    <div class="font-semibold">{site + item.modification.location}</div>
                  </div>
                  <IconArrowRight class="mx-1" />
                  <div class="items-center gap-2 flex p-2 rounded-full hover:bg-accent" onclick={() => window.open(item.modification.dest, '_blank')}>
                    <div class="font-semibold">{item.modification.dest}</div>
                    <IconExternalLink />
                  </div>
                  <div class="ml-auto text-xs">
                    {item.modificationType === ModificationType.CREATED ?
                      <>Till {new Date(item.modification.deathat).toLocaleString()}</>:
                      <>Deleted (till {new Date(item.modification.deathat).toLocaleString()})</>}
                  </div>
                </div>
              </div>
            </button>
          )}
        </For>
      </div>
    </Show>
  )
  return (
    <For each={history()!.entries}>
      {entry => <Card class="w-max m-4 w-max-lg flex">
        <CardHeader>
          <CardTitle>{entry.modificationType === ModificationType.CREATED ? 'Created' : 'Deleted'} ({entry.index})</CardTitle>
        </CardHeader>
        <CardContent>
            <CardDescription>
              From: {entry.modification.location}
            </CardDescription>
            <CardDescription>
              To: {entry.modification.dest}
            </CardDescription>
            <Show when={entry.modificationType == ModificationType.CREATED}>
              <CardDescription>
                Till: {new Date(entry.modification.deathat).toLocaleString()}
              </CardDescription>
            </Show>
          </CardContent>
        </Card>}
      </For>
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
      <ShowHistory />
    </div>
  )
}

