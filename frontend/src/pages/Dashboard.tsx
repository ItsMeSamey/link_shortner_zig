import { createSignal, For, Show, Setter } from 'solid-js'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '~/registry/ui/card'
import { Button } from '~/registry/ui/button'
import { TextField, TextFieldInput, TextFieldLabel } from '~/registry/ui/text-field'
import { AlertDialog, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader } from '@shadui/alert-dialog'
import { IconArrowRight, IconClock, IconDotsVertical, IconPlus, IconTrash } from '~/components/icons'
import { Dialog, DialogContent, DialogFooter, DialogHeader } from '@shadui/dialog'
import ModeToggle from '../components/ModeToggle'
import { Accessor } from 'solid-js'
import { showToast } from '~/registry/ui/toast'
import { Toaster } from '~/registry/ui/toast'
import { addRedirection, deleteRedirection, getRedirectionMapEntries, RedirectionInfo, site } from '../utils/fetch'

function showErrorToast(e: Error) {
  showToast( {title: e.name, description: e.message, variant: 'error', duration: 5000} )
}

function DialogueWithRedirection(
  redirection: Accessor<RedirectionInfo | null>,
  setRedirection: Setter<RedirectionInfo | null>,
  onSubmit: (location: RedirectionInfo, stopLoading: () => void) => PromiseLike<void>,
  submitName: string
) {
  let clipboardHandler: any
  const [loading, setLoading] = createSignal(false)
  function setFine(key: keyof RedirectionInfo, value: any) {
    if (!value) return
    setRedirection((old: RedirectionInfo | null): RedirectionInfo => {
      (old![key] as unknown) = value
      return old!
    })
  }

  const onpaste = (e: ClipboardEvent) => {
    if ((e.target as HTMLElement).nodeName !== 'INPUT') e.stopPropagation()

    navigator.clipboard.readText().then(text => {
      var err: Error | undefined = undefined;
      try {
        setRedirection(JSON.parse(text) as RedirectionInfo)
        return
      } catch (e) {err = e as Error}

      if ((e.target as HTMLElement).nodeName === 'INPUT') return

      showErrorToast(err)
    })
  }

  const oncopy = (e: ClipboardEvent) => {
    if ((e.target as HTMLElement).nodeName === 'INPUT') return
    e.stopPropagation()
    navigator.clipboard.writeText(JSON.stringify(redirection()))
  }

  return (
    <Dialog open={Boolean(redirection())} onOpenChange={() => setRedirection(null)}>
      <DialogContent
        ref={clipboardHandler}
        oncopy={oncopy}
        onpaste={onpaste}
      >
        <DialogHeader>
          <h3>{submitName} Redirection</h3>
        </DialogHeader>
        <div>
          <TextField>
            <TextFieldLabel>From</TextFieldLabel>
            <TextFieldInput
              placeholder="/google"
              type='text'
              value={redirection()?.location}
              onInput={(e) => { setFine('location', (e.target as HTMLInputElement).value) }
            }/>
          </TextField>
          <TextField>
            <TextFieldLabel>Destination</TextFieldLabel>
            <TextFieldInput
              placeholder="https://google.com"
              type='text'
              value={redirection()?.dest}
              onInput={(e) => { setFine('dest', (e.target as HTMLInputElement).value) }
            }/>
          </TextField>
          <TextField>
            <TextFieldLabel>Lifetime (Seconds)</TextFieldLabel>
            <TextFieldInput
              placeholder="Enter lifetime in seconds"
              type="number"
              value={redirection()?.deathat}
              onInput={(e) => { setFine('deathat', (e.target as HTMLInputElement).valueAsNumber) }
            }/>
          </TextField>
        </div>
        <DialogFooter>
          <Button onClick={() => setRedirection(null)} disabled={loading()}>Cancel</Button>
          <Button
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()

              const old = redirection()
              if (!old) {
                showErrorToast(new Error('All Fields are required'))
                return
              }
              if (old.location.startsWith(site)) {
                old.location = old.location.slice(site.length)
              } else if (old.location[0] == '/') {
                old.location = old.location.slice(1)
              }

              if (old.location.startsWith('http')) {
              showErrorToast(new Error('Invalid from, location must not include the domain'))
                return
              }

              if (!old.dest.startsWith('http') && !old.dest.includes('://')) old.dest = 'http://' + old.dest

              if (!old.location) {
                showErrorToast(new Error('All Fields are required'))
                return
              } else if (!old.dest) {
                showErrorToast(new Error('To location is required'))
                return
              } else if (!(old.deathat > 0)) {
                showErrorToast(new Error('Lifetime must be greater than 0'))
                return
              }

              setLoading(true)
              onSubmit(redirection()!, () => setLoading(false))
            }}
            disabled={loading()}
          >
            <Show when={loading()} fallback={submitName}><IconClock class='animate-spin size-6 p-0'/></Show>
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ShowAddDialog({location, setLocation, setList}: {location: Accessor<RedirectionInfo | null>, setLocation: Setter<RedirectionInfo | null>, setList: Setter<RedirectionInfo[]>}) {
  return DialogueWithRedirection(location, setLocation, async (l, stopLoading) => {
    try {
      await addRedirection(l)
      setList(old => {
        old.push(l)
        return old
      })
      showToast({title: 'Success', description: <>Redirection from {l.location} to {l.dest} with lifetime {l.deathat} Added</>, variant: 'success', duration: 5000})
      setLocation(null)
    } catch (e) {
      showErrorToast(e as Error)
    } finally {
      stopLoading()
    }
  }, 'Add')
}

function ShowUpdateDialog({location, setLocation}: {location: Accessor<RedirectionInfo | null>, setLocation: Setter<RedirectionInfo | null>}) {
  return DialogueWithRedirection(location, setLocation, async (l, stopLoading) => {
    try {
      await deleteRedirection(l.location)
      await addRedirection(l)
      showToast({title: 'Success', description: <>Redirection from {l.location} to {l.dest} with lifetime {l.deathat} Updated to {l.dest} with lifetime {l.deathat}</>, variant: 'success', duration: 5000})
      setLocation(null)

    } catch (e) {
      showErrorToast(e as Error)
    } finally {
      stopLoading()
    }
  }, 'Update')
}

function LocationList({list, setList}: {list: Accessor<RedirectionInfo[]>, setList: Setter<RedirectionInfo[]>}) {
  const [deleteDialogue, setDeleteDialogue] = createSignal<RedirectionInfo | null>(null)
  const [updateDialogue, setUpdateDialogue] = createSignal<RedirectionInfo | null>(null)

  return (
    <>
      <AlertDialog open={Boolean(deleteDialogue())}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <h3>Delete Location</h3>
          </AlertDialogHeader>
          <AlertDialogDescription>
            Are you sure you want to delete
            {deleteDialogue()?.location}
            <IconArrowRight class='stroke-foreground' />
            {deleteDialogue()?.dest}
          </AlertDialogDescription>
          <AlertDialogFooter>
            <Button onClick={() => setDeleteDialogue(null)}>Cancel</Button>
            <Button
              class='bg-red-500 hover:bg-red-700'
              onClick={() => {
                deleteRedirection(deleteDialogue()!.location).then(() => {
                  setList(old => old.filter(l => l.location !== deleteDialogue()!.location))
                  showToast({title: 'Deletion successful', description: <>Redirection from {deleteDialogue()!.location} to {deleteDialogue()!.dest} with lifetime {deleteDialogue()!.deathat} Deleted</>, variant: 'success', duration: 5000})
                  setDeleteDialogue(null)
                }).catch((e) => {
                  showErrorToast(e as Error)
                })
              }}
              color='secondary'
            >
              Delete
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <ShowUpdateDialog
        location={updateDialogue}
        setLocation={setUpdateDialogue}
      />

      <For each={list()?? []}>
        {(redirection) => (
          <span
            class='flex py-1 flex-col items-start gap-2 rounded-lg border p-3 mx-4 my-2 text-left text-sm transition-all'
          >
            <div class='flex w-full flex-col gap-1'>
              <div class='flex items-center'>
                {site + redirection.location}
                <IconArrowRight class='stroke-foreground' />
                {redirection.dest}
                <div class='ml-auto text-xs flex gap-1'>
                  <Button
                    class='bg-muted/50 hover:bg-blue-500/25 p-2 mr-2'
                    onClick={() => setUpdateDialogue(redirection)}
                  > <IconDotsVertical class='stroke-foreground' /> </Button>
                  <Button
                    class='bg-muted/50 hover:bg-red-500/25 p-2'
                    onClick={() => setDeleteDialogue(redirection)}
                  > <IconTrash class='stroke-foreground' /> </Button>
                </div>
              </div>
            </div>
          </span>
        )}
      </For>
    </>
  )
}

export default function LocationManager() {
  const [list, setList] = createSignal<RedirectionInfo[]>([], { equals: false })
  const [addDialogue, setAddDialogue] = createSignal<RedirectionInfo | null>(null)

  async function updateList() {
    try {
      const {entries} = await getRedirectionMapEntries(0, 1024)
      setList(entries)
    } catch (e) {
      showErrorToast(e as Error)
    }
  }
  updateList()

  return (
    <>
      <Toaster draggable={true} />
      <ShowAddDialog
        location={addDialogue}
        setLocation={setAddDialogue}
        setList={setList}
      />
      <Card>
        <CardHeader>
          <div class='flex flex-row items-center'>
            <div class='mr-auto'>
              <CardTitle>Redirections</CardTitle>
              <CardDescription>Manage your redirections</CardDescription>
            </div>
            <div class='mr-[-1rem] mt-[-2rem] flex flex-row items-center gap-2'>
              <div
                class='hover:bg-green-500/25 mr-2 size-9 cursor-pointer flex items-center justify-center rounded transition border border-green-500/25 animate-pulse'
                onClick={() => setAddDialogue({} as RedirectionInfo)}
              > <IconPlus class='stroke-foreground' /> </div>
              <ModeToggle/>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <LocationList list={list} setList={setList}/>
        </CardContent>
      </Card>
    </>
  )
}

