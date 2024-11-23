import { createSignal, onMount, Setter, Show } from "solid-js"
import { Button } from "../components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle
} from "../components/ui/card"
import { TextField, TextFieldInput, TextFieldLabel } from "../components/ui/text-field"
import { validateAndSaveCredentials } from "../utils/fetch"
 
export default function Login({sP}: {sP: Setter<string>}) {
  const [error, setError] = createSignal<string | null>(null)
  const [loginText, setLoginText] = createSignal<string>('>.^.<');

  onMount(() => {
    const text = 'Login to the admin panel';
    function updateLoginText(index: number) {
      setTimeout(() => {
        setLoginText(text.slice(0, index))
        updateLoginText(index + 1)
      }, 150/Math.sqrt(text.length))
    }

    setTimeout(() => updateLoginText(0), 1000)
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

