import type { NextConfig } from "next";
const config: NextConfig = {
  poweredByHeader: false,
  async redirects() {
    return [
      { source: "/about", destination: "/", permanent: true },
      ...(process.env.OI_WEB_PREVIEW === "1" ? [
        { source: "/stories/:path*", destination: "https://mat-web-production.up.railway.app/stories/:path*", permanent: false },
        { source: "/pilot", destination: "https://mat-web-production.up.railway.app", permanent: false },
        { source: "/reserve", destination: "https://mat-web-production.up.railway.app/reserve", permanent: false },
        { source: "/admin", destination: "https://mat-web-production.up.railway.app/admin", permanent: false },
      ] : []),
    ];
  },
  async headers() {
    return [{ source: "/(.*)", headers: [
      ...(process.env.OI_WEB_PREVIEW === "1" ? [{ key: "X-Robots-Tag", value: "noindex, nofollow" }] : []),
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      { key: "Permissions-Policy", value: "camera=(self), microphone=(), geolocation=()" }
    ] }];
  }
};
export default config;
