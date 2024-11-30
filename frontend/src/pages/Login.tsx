import { createSignal, onCleanup, onMount, Setter, Show } from "solid-js"
import { Button } from "~/registry/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle
} from "~/registry/ui/card"
import { TextField, TextFieldInput, TextFieldLabel } from "~/registry/ui/text-field"
import { validateAndSaveCredentials } from "../utils/fetch"
 
export default function Login({sP}: {sP: Setter<string>}) {
  const [error, setError] = createSignal<string | null>(null)
  const [loginText, setLoginText] = createSignal<string>('>.^.<');

  var keepLooping = true
  const text = 'Login to the admin panel';

  onCleanup(() => { keepLooping = false })
  onMount(() => {
    function updateLoginText(index: number, increasing: boolean = true) {
      if (!keepLooping) return
      setLoginText(text.slice(0, index))
      if (increasing) {
        if (index < text.length && increasing) {
          setTimeout(() => {
            updateLoginText(index + 1)
          }, 150/Math.sqrt(text.length))
        } else if (index == text.length && increasing) {
          setTimeout(() => {
            updateLoginText(index, false)
          }, 4000)
        }
      } else {
        if (index > 1) {
          setTimeout(() => {
            updateLoginText(index - 1, false)
          }, 50/Math.sqrt(text.length))
        } else {
          setLoginText('😊')
          setTimeout(() => {
            updateLoginText(index + 1)
          }, 1000)
        }
      }
    }

    setTimeout(() => updateLoginText(1), 1000)
  })

  var username: HTMLInputElement = undefined as any
  var password: HTMLInputElement = undefined as any
  return (
    <Card class="w-[350px] m-auto">
      <CardHeader>
        <CardTitle class="text-center">Login</CardTitle>
        <Show when={error()} fallback={
          <CardDescription class="text-center">
            {loginText()}
          </CardDescription>
        }>
          <CardDescription class="text-center text-red-500">
            {error()}
          </CardDescription>
        </Show>
      </CardHeader>
      <CardContent class="space-y-2">
        <TextField class="space-y-1">
          <TextFieldLabel>Name</TextFieldLabel>
          <TextFieldInput placeholder="Username" type="text" ref={username} />
        </TextField>
        <TextField class="space-y-1">
          <TextFieldLabel>Username</TextFieldLabel>
          <TextFieldInput placeholder="Password" type="password" ref={password} />
        </TextField>
      </CardContent>
      <CardFooter class="justify-center">
        <Button onclick={() => {
          if (username.value && password.value) {
            validateAndSaveCredentials(username.value, password.value).then(() => sP('Dashboard')).catch(e => setError(e.message))
          } else if (!username.value) {
            setError('Username is required')
          } else if (!password.value) {
            setError('Password is required')
          }
        }}>Login</Button>
      </CardFooter>
    </Card>
  )
}

