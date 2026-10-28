'use client';
import {Printer} from 'lucide-react';
export function PrintReceipt(){return <button onClick={()=>window.print()} className="bg-indigo-600 text-white px-4 py-2 rounded-xl inline-flex gap-2 items-center"><Printer size={16}/> Print / Save PDF</button>}
