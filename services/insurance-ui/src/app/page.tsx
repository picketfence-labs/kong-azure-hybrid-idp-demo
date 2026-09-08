"use client";

import { useState } from "react";

// design-brief Group2アクセスマトリクスの6API。kong/insurance-<key>.yamlのRoute path
// （例: /product）と一致させる。
const APIS = [
  "product",
  "customer",
  "simulation",
  "application",
  "policy",
  "claim",
] as const;

type ApiKey = (typeof APIS)[number];
type AccessResult = { allowed: boolean; status: number } | { error: string };
type ResultsState = Partial<Record<ApiKey, "pending" | AccessResult>>;

export default function Page() {
  const [results, setResults] = useState<ResultsState>({});

  async function checkAccess(api: ApiKey) {
    setResults((prev) => ({ ...prev, [api]: "pending" }));
    const response = await fetch(`/insurance/api/access-check?api=${api}`);
    const body = (await response.json()) as AccessResult;
    setResults((prev) => ({ ...prev, [api]: body }));
  }

  return (
    <div className="flex flex-1 flex-col min-h-0 max-w-2xl w-full mx-auto p-4 gap-4">
      <p className="text-sm text-black/70">
        各ボタンでバックエンドAPI（Kong経由、legacy-authz-adapterによるグループ判定）を呼び出し、
        自分のグループでの許可/拒否を確認します。
      </p>
      <ul className="flex flex-col gap-2">
        {APIS.map((api) => {
          const result = results[api];
          return (
            <li
              key={api}
              className="flex items-center justify-between gap-3 rounded border border-black/10 px-3 py-2"
            >
              <span className="font-mono">{api}</span>
              <div className="flex items-center gap-3">
                {result === "pending" ? (
                  <span className="text-black/50">確認中...</span>
                ) : result && "error" in result ? (
                  <span className="text-red-700 text-xs">{result.error}</span>
                ) : result ? (
                  <span
                    className={
                      result.allowed
                        ? "rounded bg-green-600/10 text-green-700 px-2 py-1 text-xs font-semibold"
                        : "rounded bg-red-600/10 text-red-700 px-2 py-1 text-xs font-semibold"
                    }
                  >
                    {result.allowed ? "許可" : "拒否"}（HTTP {result.status}）
                  </span>
                ) : null}
                <button
                  type="button"
                  onClick={() => checkAccess(api)}
                  className="rounded bg-blue-600 text-white px-3 py-1 text-sm"
                >
                  呼び出す
                </button>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
