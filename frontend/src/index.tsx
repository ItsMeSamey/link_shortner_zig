import { ColorModeProvider, ColorModeScript, createLocalStorageManager } from '@kobalte/core'
import { render } from 'solid-js/web'
import Login from './pages/Login'
import './app.css'
import { Match, Switch } from 'solid-js'
import ModeToggle from './components/ModeToggle'
import Dashboard from './pages/Dashboard'
import { selectP, setP } from './utils/stateManagement'

render(function() {
  const storageManager = createLocalStorageManager('ui-theme')
  return (
    <div class='h-screen w-screen flex flex-col'>
      <ColorModeScript storageType={storageManager.type} />
      <ColorModeProvider initialColorMode='dark' disableTransitionOnChange={false} storageManager={storageManager}>
        <Switch fallback={(() => setP('Login'))()}>
          <Match when={selectP('Login')}>
            <div class='justify-end top-0 right-0 absolute z-50 mt-2 mr-2'><ModeToggle /></div>
            <Login />
          </Match>
          <Match when={selectP('Dashboard')}>
            <Dashboard />
          </Match>
        </Switch>
      </ColorModeProvider>
    </div>
  )
}, document.getElementById('root')!)

