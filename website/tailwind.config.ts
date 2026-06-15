import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-montserrat)", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      colors: {
        brand: {
          blue: "#2559B4",
          blueLight: "#4A7FD4",
          blueDark: "#183A72",
          charcoal: "#21282F",
          charcoalLight: "#3A4550",
          silver: "#E5E5E5",
        },
      },
      boxShadow: {
        card: "0 18px 50px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.04)",
        soft: "0 8px 30px rgba(0, 0, 0, 0.35)",
      },
    },
  },
  plugins: [],
};

export default config;
