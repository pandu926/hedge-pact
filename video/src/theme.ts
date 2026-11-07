import {Easing} from 'remotion';
export const theme={colors:{bg:'#111a14',surface:'#1c2a1d',primary:'#d3fa74',text:'#f4f8ef',dim:'#a5b49b',line:'#32472b',shade:'rgba(0,0,0,.15)'},fonts:{display:'Manrope',body:'Manrope, sans-serif'},ease:{out:Easing.bezier(.16,1,.3,1),inOut:Easing.bezier(.83,0,.17,1),in:Easing.bezier(.7,0,.84,0)},spring:{smooth:{damping:20,stiffness:90,mass:1}}} as const;
