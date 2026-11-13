import type { Metadata } from 'next';
import './style.css';
export const metadata: Metadata = { title: 'People · S REST', description: 'A working Next.js client for the S users API.' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
 return <html lang="en"><body>{children}</body></html>;
}
