import { defineConfig } from 'vite'
import solid from 'vite-plugin-solid'
import { viteSingleFile } from 'vite-plugin-singlefile'
import { ViteMinifyPlugin } from 'vite-plugin-minify'
import path from 'path'

export default defineConfig({
  plugins: [
    solid(),
    viteSingleFile({
      removeViteModuleLoader: true
    }),
    ViteMinifyPlugin({}),
  ],

  resolve: {
    alias: {
      "~": path.resolve(__dirname, "./src"),
      "src": path.resolve(__dirname, "./src")
    }
  },

  build: {
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
      },
      format: {
        comments: false,
      },
    },
  },
})

