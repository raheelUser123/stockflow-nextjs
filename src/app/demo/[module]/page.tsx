import {notFound} from 'next/navigation';import {DemoWorkspace} from '@/components/demo-workspace';
const allowed=['products','suppliers','warehouses','pos','sales','analytics','audit','settings'];
export default async function Page({params}:{params:Promise<{module:string}>}){const {module}=await params;if(!allowed.includes(module))notFound();return <DemoWorkspace module={module}/>}
