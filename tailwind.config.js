/** @type {import('tailwindcss').Config} */
export default {
  content: ['./frontend/src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      colors: {
        // Chemical element colors
        carbon: '#000000',
        oxygen: '#ff0d0d',
        nitrogen: '#3050f8',
        sulfur: '#ffff30',
        phosphorus: '#ff8000',
        fluorine: '#90e050',
        chlorine: '#1ff01f',
        bromine: '#a62929',
        iodine: '#940094',
      },
    },
  },
  plugins: [],
}
