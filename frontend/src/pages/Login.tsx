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
  function getRandomEmoji() {
    const emojiRanges = [
      [0x1F600, 0x1F64F],  // Emoticons
      [0x1F680, 0x1F6FF],  // Transport and map symbols
      [0x1F700, 0x1F77F],  // Alchemical symbols
      [0x1F780, 0x1F7FF],  // Geometric Shapes
      [0x1F800, 0x1F8FF],  // Supplemental Arrows-C
      [0x1F900, 0x1F9FF],  // Supplemental Symbols and Pictographs
      [0x1F600, 0x1F64F],  // Faces (repeat for more diversity)
      [0x1F300, 0x1F5FF],  // Miscellaneous Symbols and Pictographs
    ];

    const range = emojiRanges[Math.floor(Math.random() * emojiRanges.length)];
    const emojiCodePoint = Math.floor(Math.random() * (range[1] - range[0] + 1)) + range[0];
    return String.fromCodePoint(emojiCodePoint);
  }

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
          }, 2500)
        }
      } else {
        if (index > 1) {
          setTimeout(() => {
            updateLoginText(index - 1, false)
          }, 50/Math.sqrt(text.length))
        } else {
          setLoginText(getRandomEmoji())
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

