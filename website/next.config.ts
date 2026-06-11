import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1:3000", "127.0.0.1"],
  outputFileTracingRoot: path.join(process.cwd(), ".."),
  ...(process.env.NODE_ENV === "production" ? { output: "standalone" as const } : {}),
};

export default nextConfig;
