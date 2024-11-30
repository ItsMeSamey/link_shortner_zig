import { createSignal, For, Show, Setter, onMount, onCleanup, createEffect } from 'solid-js'
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
import { AddLocation, UpdateLocation, DeleteLocation, GetLocations, LocationInfo } from '../utils/fetch'
import { IconClock, IconDotsVertical, IconPlus, IconTrash } from '~/components/icons'
import { Badge } from '~/registry/ui/badge'
import { Dialog, DialogContent, DialogFooter, DialogHeader } from '@shadui/dialog'
import ModeToggle from '../components/ModeToggle'
import { Accessor } from 'solid-js'
import { showToast } from '~/registry/ui/toast'
import { Toaster } from '~/registry/ui/toast'

const [geolocation, setGeolocation] = createSignal<{lat?: number, long?: number}>({})

function showErrorToast(e: Error) {
  showToast( {title: 'Error ' + e.name, description: e.message, variant: 'error', duration: 5000} )
}

function DialogueWithLocation(
  location: Accessor<LocationInfo | null>,
  setLocation: Setter<LocationInfo | null>,
  onSubmit: (location: LocationInfo, stopLoading: () => void) => void,
  submitName: string
) {
  let clipboardHandler: any
  const [loading, setLoading] = createSignal(false)
  function setFine(key: keyof(LocationInfo), value: any) {
    if (!value) return
    setLocation({ ...location()!, [key]: value })
  }

  const onpaste = (e: ClipboardEvent) => {
    if ((e.target as HTMLElement).nodeName === 'INPUT') return
    e.stopPropagation()
    navigator.clipboard.readText().then(text => {
      var err: Error | undefined = undefined;
      try {
        const parsed = JSON.parse(text)
        setFine('lat', parsed.lat)
        setFine('long', parsed.long)
        setFine('names', parsed.names)
        setFine('misspellings', parsed.misspellings)
        return
      } catch (e) {err = e as Error}
      try {
        const coords = text.split(',').map(Number)
        setFine('lat', coords[0])
        setFine('long', coords[1])
        return
      } catch (e) {err = e as Error}

      showErrorToast(err)
    })
  }

  const oncopy = (e: ClipboardEvent) => {
    e.stopPropagation()
    navigator.clipboard.writeText(JSON.stringify(location()))
  }

  if (location()) {
    setLocation(old => {
      old!.lat = old!.lat ?? geolocation().lat ?? 0
      old!.long = old!.long ?? geolocation().long ?? 0
      return old
    })
  }

  return (
    <Dialog open={Boolean(location())} onOpenChange={() => setLocation(null)}>
      <DialogContent
        ref={clipboardHandler}
        oncopy={oncopy}
        onpaste={onpaste}
      >
        <DialogHeader>
          <h3>{submitName} Location</h3>
        </DialogHeader>
        <div>
          <TextField>
            <TextFieldLabel>Location Name</TextFieldLabel>
            <TextFieldInput
              placeholder='Location Name'
              type='text'
              value={location()?.names?.join(', ')}
              onInput={(e) => {
                setFine('names', (e.target as HTMLInputElement).value.split(',').map(s => s.trim()))
              }
            }/>
          </TextField>
          <TextField>
            <TextFieldLabel>Misspellings</TextFieldLabel>
            <TextFieldInput
              placeholder='Misspellings'
              type='text'
              value={location()?.misspellings?.join(', ')}
              onInput={(e) => {
                setFine('misspellings', (e.target as HTMLInputElement).value.split(',').map(s => s.trim()))
              }
            }/>
          </TextField>
          <TextField>
            <TextFieldLabel>Latitude</TextFieldLabel>
            <TextFieldInput
              placeholder={String(geolocation().lat ?? 'Latitude')}
              min={-90}
              max={90}
              value={location()?.lat ?? geolocation().lat}
              type='number'
              onInput={(e) => {
                setFine('lat', (e.target as HTMLInputElement).valueAsNumber)
              }
            }/>
          </TextField>
          <TextField>
            <TextFieldLabel>Longitude</TextFieldLabel>
            <TextFieldInput
              placeholder={String(geolocation().long ?? 'Longitude')}
              min={-180}
              max={180}
              value={location()?.long ?? geolocation().long}
              type='number'
              onInput={(e) => {
                setFine('long', (e.target as HTMLInputElement).valueAsNumber)
              }
            }/>
          </TextField>
        </div>
        <DialogFooter>
          <Button onClick={() => setLocation(null)} disabled={loading()}>Cancel</Button>
          <Button
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              setLoading(true)
              onSubmit(location()!, () => setLoading(false))
            }}
            disabled={loading()}
          >
            <Show when={loading()} fallback={submitName}><IconClock class='animate-spin size-6 p-0' /></Show>
          </Button>

        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ShowAddDialog({location, setLocation, setList}: {location: Accessor<LocationInfo | null>, setLocation: Setter<LocationInfo | null>, setList: Setter<LocationInfo[]>}) {
  return DialogueWithLocation(location, setLocation, (l, stopLoading) => {
    if (!l) return stopLoading()
    if (!l.lat || !l.long) {
      l.lat = geolocation().lat ?? (() => {throw new Error('No geolocation found')})()
      l.long = geolocation().long ?? (() => {throw new Error('No geolocation found')})()
    }

    if (l.misspellings) l.misspellings.map(m => m.trim()).filter(m => m.length > 0)
    if (l.names) l.names.map(n => n.trim()).filter(n => n.length > 0)

    AddLocation(l).then(() => {
      setList(old => {
        old.push(l)
        return old
      })
      showToast({title: 'Success', description: <>Location {l.names.join(', ')}({l.long}, {l.lat}) Added</>, variant: 'success', duration: 5000})
      setLocation(null)
    }).catch(e => showToast(
      {title: 'Error', description: e.message, variant: 'error', duration: 5000}
    )).finally(stopLoading)
  }, 'Add')
}

function ShowUpdateDialog({location, setLocation}: {location: Accessor<LocationInfo | null>, setLocation: Setter<LocationInfo | null>}) {
  return DialogueWithLocation(location, setLocation, (l, stopLoading) => {
    if (!l) return stopLoading()
    if (!l.lat || !l.long) {
      l.lat = geolocation().lat ?? (() => {throw new Error('No geolocation found')})()
      l.long = geolocation().long ?? (() => {throw new Error('No geolocation found')})()
    }

    if (l.misspellings) l.misspellings.map(m => m.trim()).filter(m => m.length > 0)
    if (l.names) l.names.map(n => n.trim()).filter(n => n.length > 0)

    UpdateLocation(l).then(() => {
      showToast({title: 'Success', description: <>Location {l.names.join(', ')}({l.long}, {l.lat}) Updated Successfully</>, variant: 'success', duration: 5000})
      setLocation(null)
    }).catch(e => showToast(
      {title: 'Error', description: e.message, variant: 'error', duration: 5000}
    )).finally(stopLoading)
  }, 'Update')
}

function AsBadges({keys, ...props}: {vals: string[]} extends any? any: any) {
  return <For each={keys}>{key => <Badge {...props}>{key}</Badge>}</For>
}

function LocationList({list, setList}: {list: Accessor<LocationInfo[]>, setList: Setter<LocationInfo[]>}) {
  const [deleteDialogue, setDeleteDialogue] = createSignal<LocationInfo | null>(null)
  const [updateDialogue, setUpdateDialogue] = createSignal<LocationInfo | null>(null)

  return (
    <>
      <AlertDialog open={Boolean(deleteDialogue())}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <h3>Delete Location</h3>
          </AlertDialogHeader>
          <AlertDialogDescription>
            Are you sure you want to delete ({deleteDialogue()?.lat}, {deleteDialogue()?.long})
            <AsBadges keys={deleteDialogue()?.names} class='bg-muted/50 mr-1 text-foreground hover:bg-muted' />
            <AsBadges keys={deleteDialogue()?.misspellings} class='bg-muted/50 mr-1 text-foreground hover:bg-muted' />
          </AlertDialogDescription>
          <AlertDialogFooter>
            <Button onClick={() => setDeleteDialogue(null)}>Cancel</Button>
            <Button
              class='bg-red-500 hover:bg-red-700'
              onClick={() => {
                DeleteLocation(deleteDialogue()!.id).then(() => {
                  const toDel = deleteDialogue()!
                  setList(old => old.filter(l => l.id !== toDel.id))
                  showToast({title: 'Deletion successful', description: <>Location {toDel.names.join(', ')}({toDel.long}, {toDel.lat}) Deleted</>, variant: 'success', duration: 5000})
                  setDeleteDialogue(null)
                }).catch((e) => {
                  showToast({title: 'Error', description: e.message, variant: 'error', duration: 5000})
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
        {(location) => (
          <span
            class='flex py-1 flex-col items-start gap-2 rounded-lg border p-3 mx-4 my-2 text-left text-sm transition-all'
          >
            <div class='flex w-full flex-col gap-1'>
              <div class='flex items-center'>
                <span class='mr-3'>
                  <TextField class='bg-muted/50 rounded-lg px-1 mb-1'> Lat: {location.lat.toFixed(4)} </TextField>
                  <TextField class='bg-muted/50 rounded-lg px-1 mt-1'> Lon: {location.long.toFixed(4)} </TextField>
                </span>
                <AsBadges keys={location.names} class='bg-muted/50 mr-1 text-foreground hover:bg-muted' />
                <div class='ml-auto text-xs flex gap-1'>
                  <Button
                    class='bg-muted/50 hover:bg-blue-500/25 p-2 mr-2'
                    onClick={() => setUpdateDialogue(location)}
                  > <IconDotsVertical class='stroke-foreground' /> </Button>
                  <Button
                    class='bg-muted/50 hover:bg-red-500/25 p-2'
                    onClick={() => setDeleteDialogue(location)}
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
  var watchId: number

  createEffect(() => {
    console.log(geolocation())
  })

  onMount(() => {
    watchId = navigator.geolocation.watchPosition((w) => {
      setGeolocation({
        lat: w.coords.latitude,
        long: w.coords.longitude,
      })
    }, (e) => {
      showToast({title: 'Location Error', description: e.message, variant: 'error', duration: 5000})
    }, { enableHighAccuracy: true })
  })

  onCleanup(() => {
    navigator.geolocation.clearWatch(watchId)
  })

  const [error, setError] = createSignal<string>('')
  const [list, setList] = createSignal<LocationInfo[]>([], { equals: false })
  const [addDialogue, setAddDialogue] = createSignal<LocationInfo | null>(null)

  function updateLocationsList() { GetLocations().then(setList).catch(setError) }
  updateLocationsList()

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
              <CardTitle>Locations</CardTitle>
              <CardDescription>Manage your locations</CardDescription>
            </div>
            <span class='absolute top-1 left-1/2 -translate-x-1/2 text-foreground p-2 rounded py-1 px-2 border border-grey-500/50 bg-muted/50 text-sm max-sm:text-xs break-keep max-sm:p-0'>
              {geolocation().lat?.toFixed(7)}, {geolocation().long?.toFixed(7)}
            </span>
            <div class='mr-[-1rem] mt-[-2rem] flex flex-row items-center gap-2'>
              <div
                class='hover:bg-green-500/25 mr-2 size-9 cursor-pointer flex items-center justify-center rounded transition border border-green-500/25 animate-pulse'
                onClick={() => setAddDialogue({} as LocationInfo)}
              > <IconPlus class='stroke-foreground' /> </div>
              <ModeToggle/>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <Show when={error()}>
            <span class='flex flex-col gap-2 text-red-500 text-center px-10'>
              {error()}
            </span>
          </Show>
          <LocationList list={list} setList={setList}/>
        </CardContent>
      </Card>
    </>
  )
}

