import {handleWebConfig} from './handler.mjs';

Deno.serve((request: Request)=>handleWebConfig(request,(name: string)=>Deno.env.get(name)));
