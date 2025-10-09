/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    "./index.html",
    "./client/**/*.{js,ts,jsx,tsx}",
  ],
  safelist: [
    'whitespace-nowrap',
    'overflow-hidden',
    'text-ellipsis',
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
