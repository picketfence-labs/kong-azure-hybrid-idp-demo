import type { Metadata } from "next";
import { headers } from "next/headers";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Kong Insurance Demo",
  description: "Kong Gateway ADFS OIDC x レガシー認可ロジック再現デモ",
};

// ログイン中のグループIDはKong(kong/insurance-ui-route.yaml)のopenid-connectが
// upstream_headersでID トークンのクレームをそのままこのアプリへ転送する
// （design-brief Group2「2. 要件」、属性値の正規化自体はADFS側で完了している前提）。
// このアプリ自身はOAuthクライアントを持たない（services/chat-uiと同じ方針）。
//
// 未ログイン状態のHTMLはそもそも存在しない: このRoute自体がopenid-connectのセッション認証
// で保護されているため、未ログインでアクセスすると常にADFSへのリダイレクトが発生する
// （Group 1のkong/login-route.yamlと同じ挙動。design-brief 検証方法1点目、
// TESTING.md Group2シナリオ①）。そのため「未ログイン」表示・ログインボタンは
// 実際には到達しない防御的な表示として残している。
export default async function RootLayout({ children }: LayoutProps<"/">) {
  const headerList = await headers();
  const groupId = headerList.get("x-adfs-group-claim");

  return (
    <html
      lang="ja"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <header className="flex items-center justify-between border-b border-black/10 px-4 py-2 text-sm">
          <span className="font-semibold">Kong Insurance Demo（Group 2）</span>
          {groupId ? (
            <div className="flex items-center gap-3">
              <span>
                ログイン中: グループ <code>{groupId}</code>
              </span>
              <form action="/insurance/?logout" method="POST">
                <button
                  type="submit"
                  className="rounded border border-black/20 px-2 py-1 hover:bg-black/5"
                >
                  ログアウト
                </button>
              </form>
            </div>
          ) : (
            <span className="text-black/50">未ログイン</span>
          )}
        </header>
        <main className="flex-1 flex flex-col min-h-0">{children}</main>
      </body>
    </html>
  );
}
