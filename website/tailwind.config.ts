import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          blue: "#007AFF",
          blueDark: "#003366",
          green: "#4CD964",
          orange: "#FF9500",
          purple: "#5856D6",
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
