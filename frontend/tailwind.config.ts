import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      screens: {
        'xs': '375px',
      },
      spacing: {
        '18': '4.5rem',
        '22': '5.5rem',
      },
      colors: {
        'ella': {
          'rose': '#E8A0BF',
          'gold': '#D4AF37',
          'dark': '#1a1a2e',
          'light': '#f8f4f0',
        },
      },
    },
  },
  plugins: [],
}
export default config
