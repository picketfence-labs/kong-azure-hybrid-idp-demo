"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  IDENTITIES,
  IDENTITY_LABELS,
  isAuthStateChangedMessage,
  isAuthStatus,
  type AuthStatus,
  type Identity,
} from "@/lib/auth";

type StatusState = "checking" | "signed-out" | "error" | AuthStatus;

const INITIAL_STATUS: Record<Identity, StatusState> = {
  entra: "checking",
  adfs: "checking",
};

// ADFSセッションから直接呼べるデモ用API（TESTING.md「Group 2」節の権限差確認用）。
// bearerトークンの別取得を要求せず、ログイン済みのブラウザセッションだけで200/403の違いを見せる。
const DEMO_APIS = [
  { key: "application", label: "Application API" },
  { key: "claim", label: "Claim API" },
] as const;

type DemoApiKey = (typeof DEMO_APIS)[number]["key"];

type ApiCallState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "allowed"; httpStatus: number }
  | { status: "denied"; httpStatus: number }
  | { status: "error"; httpStatus?: number };

const INITIAL_API_RESULTS: Record<DemoApiKey, ApiCallState> = {
  application: { status: "idle" },
  claim: { status: "idle" },
};

function describeApiCall(state: ApiCallState) {
  switch (state.status) {
    case "idle":
      return "未実行";
    case "loading":
      return "実行中";
    case "allowed":
      return `許可されました（HTTP ${state.httpStatus}）`;
    case "denied":
      return `権限がありません（HTTP ${state.httpStatus}）`;
    case "error":
      return state.httpStatus
        ? `想定外のエラー（HTTP ${state.httpStatus}）`
        : "想定外のエラー";
  }
}

function describeStatus(status: StatusState) {
  if (status === "checking") {
    return "状態を確認中";
  }
  if (status === "signed-out") {
    return "未認証";
  }
  if (status === "error") {
    return "状態を確認できません";
  }
  return `認証済み、検証済み属性${status.attributePresent ? "あり" : "なし"}`;
}

export default function Page() {
  const [statuses, setStatuses] =
    useState<Record<Identity, StatusState>>(INITIAL_STATUS);
  const [popupBlocked, setPopupBlocked] = useState<Identity | null>(null);
  const popups = useRef<Partial<Record<Identity, Window>>>({});
  const [apiResults, setApiResults] =
    useState<Record<DemoApiKey, ApiCallState>>(INITIAL_API_RESULTS);

  async function callDemoApi(key: DemoApiKey) {
    setApiResults((current) => ({ ...current, [key]: { status: "loading" } }));
    try {
      const response = await fetch(`/adfs/call/${key}`, {
        cache: "no-store",
        credentials: "same-origin",
        redirect: "manual",
      });

      if (response.status === 200) {
        setApiResults((current) => ({
          ...current,
          [key]: { status: "allowed", httpStatus: response.status },
        }));
        return;
      }

      if (response.status === 403) {
        setApiResults((current) => ({
          ...current,
          [key]: { status: "denied", httpStatus: response.status },
        }));
        return;
      }

      setApiResults((current) => ({
        ...current,
        [key]: { status: "error", httpStatus: response.status },
      }));
    } catch {
      setApiResults((current) => ({
        ...current,
        [key]: { status: "error" },
      }));
    }
  }

  const refreshStatus = useCallback(async (identity: Identity) => {
    try {
      const response = await fetch(`/${identity}/auth/status`, {
        cache: "no-store",
        credentials: "same-origin",
        redirect: "manual",
      });

      if (response.status === 401) {
        setStatuses((current) => ({ ...current, [identity]: "signed-out" }));
        return;
      }

      if (!response.ok) {
        setStatuses((current) => ({ ...current, [identity]: "error" }));
        return;
      }

      const status: unknown = await response.json();
      if (!isAuthStatus(status, identity)) {
        setStatuses((current) => ({ ...current, [identity]: "error" }));
        return;
      }
      setStatuses((current) => ({ ...current, [identity]: status }));
    } catch {
      setStatuses((current) => ({ ...current, [identity]: "error" }));
    }
  }, []);

  useEffect(() => {
    const refreshAll = () => {
      for (const identity of IDENTITIES) {
        void refreshStatus(identity);
      }
    };

    const initial = window.setTimeout(refreshAll, 0);
    const interval = window.setInterval(refreshAll, 3000);

    return () => {
      window.clearTimeout(initial);
      window.clearInterval(interval);
    };
  }, [refreshStatus]);

  useEffect(() => {
    function handleMessage(event: MessageEvent) {
      if (
        event.origin !== window.location.origin ||
        !isAuthStateChangedMessage(event.data) ||
        event.source !== popups.current[event.data.identity]
      ) {
        return;
      }

      void refreshStatus(event.data.identity);
    }

    window.addEventListener("message", handleMessage);
    return () => window.removeEventListener("message", handleMessage);
  }, [refreshStatus]);

  function openLogin(identity: Identity) {
    const popup = window.open(
      `/${identity}/auth/start`,
      `insurance-auth-${identity}`,
      "popup,width=720,height=760",
    );

    if (!popup) {
      setPopupBlocked(identity);
      return;
    }

    popups.current[identity] = popup;
    setPopupBlocked(null);
  }

  async function logout(identity: Identity) {
    setStatuses((current) => ({ ...current, [identity]: "checking" }));
    try {
      await fetch(`/${identity}/auth/logout`, {
        method: "POST",
        credentials: "same-origin",
        redirect: "manual",
      });
    } finally {
      await refreshStatus(identity);
    }
  }

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-1 flex-col gap-6 p-6">
      <section className="space-y-2">
        <h1 className="text-2xl font-semibold">保険APIの認証経路PoC</h1>
        <p className="text-sm text-black/70 dark:text-white/70">
          この画面は未認証でも維持されます。認証はIdPごとの別画面で行い、
          完了通知を受けた後もsession endpointで状態を再確認します。
        </p>
      </section>

      <section className="grid gap-4 md:grid-cols-2" aria-label="認証経路">
        {IDENTITIES.map((identity) => {
          const status = statuses[identity];
          const authenticated =
            typeof status === "object" ? status : undefined;

          return (
            <article
              key={identity}
              className="rounded-lg border border-black/15 p-4 dark:border-white/20"
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h2 className="font-semibold">{IDENTITY_LABELS[identity]}</h2>
                  <p className="mt-1 text-sm" aria-live="polite">
                    {describeStatus(status)}
                  </p>
                </div>
                <span
                  className={`rounded px-2 py-1 text-xs font-medium ${
                    authenticated
                      ? "bg-green-600/10 text-green-700 dark:text-green-300"
                      : "bg-black/5 text-black/60 dark:bg-white/10 dark:text-white/70"
                  }`}
                >
                  {authenticated ? "signed in" : "signed out"}
                </span>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => openLogin(identity)}
                  className="rounded bg-blue-600 px-3 py-2 text-sm text-white"
                >
                  別画面でログイン
                </button>
                <button
                  type="button"
                  onClick={() => logout(identity)}
                  disabled={!authenticated}
                  className="rounded border border-black/20 px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-40 dark:border-white/25"
                >
                  この経路だけログアウト
                </button>
              </div>

              {popupBlocked === identity && (
                <p className="mt-3 text-sm text-amber-700 dark:text-amber-300">
                  別画面を開けませんでした。{" "}
                  <a
                    href={`/${identity}/auth/start`}
                    target="_blank"
                    rel="noreferrer"
                    className="underline"
                  >
                    ログイン画面を開く
                  </a>
                </p>
              )}

              {identity === "adfs" && authenticated && (
                <div className="mt-4 space-y-2 border-t border-black/10 pt-4 dark:border-white/15">
                  <p className="text-xs text-black/60 dark:text-white/60">
                    ログイン中のユーザーの権限で、デモ用APIを呼び出します（ユーザーによって結果が変わります）。
                  </p>
                  {DEMO_APIS.map((api) => (
                    <div
                      key={api.key}
                      className="flex flex-wrap items-center gap-2"
                    >
                      <button
                        type="button"
                        onClick={() => callDemoApi(api.key)}
                        className="rounded border border-black/20 px-3 py-2 text-sm dark:border-white/25"
                      >
                        {api.label}を呼ぶ
                      </button>
                      <span className="text-sm" aria-live="polite">
                        {describeApiCall(apiResults[api.key])}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </article>
          );
        })}
      </section>

      <section className="rounded-lg border border-dashed border-black/20 p-4 text-sm dark:border-white/25">
        <h2 className="font-semibold">このPoCに含めないもの</h2>
        <p className="mt-2 text-black/70 dark:text-white/70">
          上記のADFSデモAPIは、TESTING.md「Group 2」節の権限差確認だけを目的にした最小限の呼び出しです。
          PostgreSQLマスタ、実行イベントと図の連動、全6 API・7 Route構成への対応は後続gateで追加します。
        </p>
      </section>
    </div>
  );
}
