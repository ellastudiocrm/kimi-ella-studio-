import type { Config } from 'tailwindcss'

// Paleta alinhada ao site oficial (ellastudioblz.com.br)
const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      screens: {
        xs: '375px',
      },
      spacing: {
        '18': '4.5rem',
        '22': '5.5rem',
      },
      fontFamily: {
        serif: ['var(--font-cormorant)', 'Georgia', 'serif'],
        sans: ['var(--font-jost)', 'system-ui', 'sans-serif'],
      },
      colors: {
        ella: {
          rose: '#AE7667', // cor principal (botões, destaques)
          'rose-deep': '#9D5E52',
          blush: '#DBAA9E',
          dark: '#412D2A', // texto
          muted: '#826C67', // texto secundário
          light: '#FFF8F6', // fundo
          card: '#FFF4F1',
          soft: '#F7E7E2',
          accent: '#F4D6CF',
          line: '#EED9D2',
        },
        men: {
          ink: '#2A2622',
          stone: '#F6F2EC',
          line: '#E4DDD3',
          muted: '#6F665E',
          accent: '#8A6450',
        },
      },
      boxShadow: {
        suave: '0 10px 30px -12px rgba(65, 45, 42, 0.18)',
      },
    },
  },
  plugins: [],
}
export default config
