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
            </article>
          );
        })}
      </section>

      <section className="rounded-lg border border-dashed border-black/20 p-4 text-sm dark:border-white/25">
        <h2 className="font-semibold">このPoCに含めないもの</h2>
        <p className="mt-2 text-black/70 dark:text-white/70">
          API認可、PostgreSQLマスタ、実行イベントと図の連動は後続gateで追加します。
          この段階では認証状態と検証済み属性の有無だけを表示します。
        </p>
      </section>
    </div>
  );
}
