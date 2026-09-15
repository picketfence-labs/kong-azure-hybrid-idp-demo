import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "Kong Hybrid IdP Insurance Demo",
  description: "Entra ID and ADFS authentication path verification",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="ja" className="h-full antialiased">
      <body className="min-h-full flex flex-col">
        <header className="border-b border-black/10 px-4 py-3 text-sm dark:border-white/15">
          <span className="font-semibold">Kong Hybrid IdP Insurance Demo</span>
        </header>
        <main className="flex-1 flex flex-col min-h-0">{children}</main>
      </body>
    </html>
  );
}
