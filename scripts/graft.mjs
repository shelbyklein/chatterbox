// Project-local development tooling; not part of the Chatterbox app, its iOS companion or its MCP server.
import {existsSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const script=fileURLToPath(import.meta.url);
const cli=fileURLToPath(new URL('../node_modules/@nanonets/graft/dist/cli.js',import.meta.url));
process.chdir(root);
process.env.DO_NOT_TRACK='1';
process.env.GRAFT_NO_GITIGNORE='1';
process.env.GRAFT_NO_IGNORE='1';

if(process.argv[2]==='setup'){
 if(!existsSync(cli))throw Error('Run npm install before configuring Graft.');
 const codex=path.join(root,'.codex/config.toml'),claude=path.join(root,'.mcp.json');
 const old=existsSync(codex)?readFileSync(codex,'utf8'):'';
 const config=existsSync(claude)?JSON.parse(readFileSync(claude,'utf8')):{};
 const spec={command:process.execPath,args:[script,'mcp']};
 const section=`[mcp_servers.graft_development]\ncommand = ${JSON.stringify(spec.command)}\nargs = ${JSON.stringify(spec.args)}\nstartup_timeout_sec = 30\ntool_timeout_sec = 120\n`;
 if(old.includes('[mcp_servers.graft_development]')&&!old.includes(section.trim()))throw Error('Existing Codex Graft configuration differs; review it before replacing.');
 if(config.mcpServers?.graft_development&&JSON.stringify(config.mcpServers.graft_development)!==JSON.stringify(spec))throw Error('Existing Claude Graft configuration differs; review it before replacing.');
 mkdirSync(path.dirname(codex),{recursive:true});
 if(!old.includes('[mcp_servers.graft_development]'))writeFileSync(codex,old+'\n'+section,{mode:0o600});
 config.mcpServers??={};
 config.mcpServers.graft_development=spec;
 writeFileSync(claude,JSON.stringify(config,null,2)+'\n',{mode:0o600});
 console.log('Configured graft_development for this checkout in .codex/config.toml and .mcp.json. Run npm run graft:build, then reopen your development session.');
}else{
 process.argv[1]=cli;
 await import(cli);
}
