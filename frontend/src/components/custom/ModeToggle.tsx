import { Match, Switch } from 'solid-js'
import { useColorMode } from '@kobalte/core'
import { Button } from '../ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger
} from '../ui/dropdown-menu'

import { IconSun, IconMoon, IconLaptop } from '../icons'

export default function ModeToggle() {
  const { colorMode, setColorMode } = useColorMode()

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

