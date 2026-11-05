import type { NextConfig } from "next";
const pilot = "https://benchmark-pilot.deep-chime-2567.chatgpt.site";
const config: NextConfig = {
  poweredByHeader: false,
  async headers() {return [{source:"/(.*)",headers:[
    {key:"X-Robots-Tag",value:"noindex, nofollow"},
    {key:"X-Content-Type-Options",value:"nosniff"},
    {key:"X-Frame-Options",value:"DENY"},
    {key:"Referrer-Policy",value:"strict-origin-when-cross-origin"},
    {key:"Permissions-Policy",value:"camera=(self), microphone=(), geolocation=()"},
  ]}];},
  async redirects() { return [
    {source:"/benchmark",destination:"https://benchmark-team.deep-chime-2567.chatgpt.site/benchmark",permanent:false},
    {source:"/concepts/:path*",destination:"https://benchmark-team.deep-chime-2567.chatgpt.site/concepts/:path*",permanent:false},
    {source:"/about",destination:"/",permanent:true},
    {source:"/stories/:path*",destination:`${pilot}/stories/:path*`,permanent:false},
    {source:"/pilot",destination:pilot,permanent:false},
    {source:"/reserve",destination:`${pilot}/reserve`,permanent:false},
    {source:"/admin",destination:`${pilot}/admin`,permanent:false},
  ]; },
};
export default config;
