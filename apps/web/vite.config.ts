import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { drainRankOllamaPlugin } from './src/server/drainRankOllama.js'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), drainRankOllamaPlugin()],
})
