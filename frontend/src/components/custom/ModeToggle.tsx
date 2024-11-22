import { Match, Switch } from 'solid-js'
import { useColorMode } from '@kobalte/core'
import { Button } from '../ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger
} from '../ui/dropdown-menu'

export default function ModeToggle() {
  const { colorMode, setColorMode } = useColorMode()

  const IconSun = (props: any) => <svg class='mr-2 size-4' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' {...props}>
    <path d='M12 12m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0'></path>
    <path d='M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7'></path>
  </svg>

  const IconMoon = (props: any) => <svg class='mr-2 size-4' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' {...props}>
    <path d='M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454z'></path>
  </svg>

  const IconLaptop = (props: any) => <svg class='mr-2 size-4' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' {...props}>
    <path d='M3 19l18 0'></path>
    <path d='M5 6m0 1a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1z'></path>
  </svg>

  return (
    <DropdownMenu>
      <DropdownMenuTrigger as={Button<'button'>} variant='ghost' size='sm' class='w-9 px-0'>
        <Switch>
          <Match when={colorMode() === 'light'}>
            <IconSun class='size-6 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0' />
          </Match>
          <Match when={colorMode() === 'dark'}>
            <IconMoon class='size-6 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100' />
          </Match>
        </Switch>
      </DropdownMenuTrigger>
      <DropdownMenuContent>
        <DropdownMenuItem onSelect={() => setColorMode('light')}>
          <IconSun class='mr-2 size-4'/>
          <span>Light</span>
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => setColorMode('dark')}>
          <IconMoon class='mr-2 size-4'/>
          <span>Dark</span>
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => setColorMode('system')}>
          <IconLaptop class='mr-2 size-4'/>
          <span>System</span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

