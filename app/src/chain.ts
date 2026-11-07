import {createPublicClient,http,defineChain,type Address,type Abi,formatEther,decodeEventLog} from 'viem';
import {baseSepolia,unichainSepolia} from 'viem/chains';
import abis from './abis.json';
import manifest from './manifest.json';
export {manifest};
export const abi=abis as Record<string,Abi>;
export const clients={base:createPublicClient({chain:baseSepolia,transport:http('https://base-sepolia-rpc.publicnode.com',{retryCount:3,retryDelay:800})}),unichain:createPublicClient({chain:unichainSepolia,transport:http('https://sepolia.unichain.org',{retryCount:3,retryDelay:800})}),lasna:createPublicClient({chain:defineChain({id:5318007,name:'Reactive Lasna',nativeCurrency:{name:'lREACT',symbol:'lREACT',decimals:18},rpcUrls:{default:{http:['https://lasna-rpc.rnk.dev']}}}),transport:http('https://lasna-rpc.rnk.dev',{retryCount:3})})};
export type Net=keyof typeof clients;
export const explorer={base:'https://sepolia.basescan.org',unichain:'https://unichain-sepolia.blockscout.com',lasna:'https://lasna.reactscan.net'};
export const shorten=(s:string)=>s?`${s.slice(0,6)}…${s.slice(-4)}`:'—';
export const quantity=(q:bigint|undefined)=>q===undefined?'—':Number(formatEther(q)).toLocaleString('en-US',{maximumFractionDigits:4});
export async function read(net:Net,address:Address,contract:string,fn:string,args:readonly unknown[]=[]):Promise<any>{return clients[net].readContract({address,abi:abi[contract],functionName:fn,args});}
export interface Activity {network:Net;hash:string;block:string;event:string;address:string}
// RPC providers cap log ranges. Backfill never asks for more than 500 blocks.
export async function activity(net:Net,address:Address,from:bigint):Promise<Activity[]>{
 const c=clients[net];const latest=await c.getBlockNumber();const key=`hp:v1:${net}:${address}`;
 let cache:{through:string;rows:Activity[]};try{cache=JSON.parse(localStorage.getItem(key)||'null')||{through:(from-1n).toString(),rows:[]};}catch{cache={through:(from-1n).toString(),rows:[]};}
 let start=BigInt(cache.through)+1n;if(start<from)start=from;
 // Incremental batches persist on every page, so reconnect resumes instead of restarting.
 for(;start<=latest;start+=500n){const end=start+499n>latest?latest:start+499n;const logs=await c.getLogs({address,fromBlock:start,toBlock:end});for(const l of logs){cache.rows.push({network:net,hash:l.transactionHash,block:l.blockNumber.toString(),event:(()=>{try{return decodeEventLog({abi:address.toLowerCase()===manifest.base.SourceFactory.toLowerCase()?abi.SourceFactory:abi.SpotFactory,data:l.data,topics:l.topics}).eventName||'Event';}catch{return 'Contract event';}})(),address:l.address});}cache.through=end.toString();cache.rows=cache.rows.slice(-400);localStorage.setItem(key,JSON.stringify(cache));}
 return cache.rows.filter((r,i,a)=>a.findIndex(x=>x.hash===r.hash)===i).reverse();
}
