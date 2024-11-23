import { ColorModeProvider, ColorModeScript, createLocalStorageManager } from '@kobalte/core';
import { render } from 'solid-js/web';
import Login from './pages/Login';
import './app.css'
import { createSignal, Match, Switch } from 'solid-js';
import ModeToggle from './components/custom/ModeToggle';
import { loginData } from './utils/fetch';
import Dashboard from './pages/Dashboard';

const [page, setPage] = createSignal<string>(loginData.get()? 'Dashboard': 'Login');

render(function() {
  const storageManager = createLocalStorageManager('ui-theme')
  return (
    <>
      <ColorModeScript storageType={storageManager.type} />
      <ColorModeProvider initialColorMode='dark' storageManager={storageManager}>
        <div class='h-screen w-screen flex flex-col'>
          <Switch>
            <Match when={page() === 'Login'}>
              <div class='flex justify-end'>
                <ModeToggle />
              </div>
              <Login sP={setPage} />
            </Match>
            <Match when={page() === 'Dashboard'}>
              <Dashboard sP={setPage} />
            </Match>
          </Switch>
        </div>
      </ColorModeProvider>
    </>
  );
}, document.getElementById('root')!);

