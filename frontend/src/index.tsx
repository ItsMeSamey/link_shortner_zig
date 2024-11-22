import { ColorModeProvider, ColorModeScript, createLocalStorageManager } from '@kobalte/core';
import { render } from 'solid-js/web';
import Login from './pages/Login';
import './app.css'
import { createSignal, Match, Switch } from 'solid-js';
import ModeToggle from './components/custom/ModeToggle';
import { loginData } from './fetch';

const [page, setPage] = createSignal<string>(loginData.get()? 'Dashboard': 'Login');

render(function() {
  const storageManager = createLocalStorageManager('ui-theme')
  return (
    <>
      <ColorModeScript storageType={storageManager.type} />
      <ColorModeProvider initialColorMode='dark' storageManager={storageManager}>
        <div class='h-screen w-screen flex flex-col'>
          <div class='flex justify-end'>
            <ModeToggle />
          </div>
          <Switch>
            <Match when={page() === 'Login'}>
              <Login setPage={setPage} />
            </Match>
          </Switch>
        </div>
      </ColorModeProvider>
    </>
  );
}, document.getElementById('root')!);

