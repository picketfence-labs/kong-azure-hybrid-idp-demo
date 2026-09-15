import { describe, expect, test } from "bun:test";
import { GET } from "./route";

function context(identity: string) {
  return { params: Promise.resolve({ identity }) };
}

describe("auth status route", () => {
  test("reports only whether Kong supplied a verified attribute", async () => {
    const response = await GET(
      new Request("http://localhost/api/auth-status/entra", {
        headers: { "x-demo-verified-attribute": "group-a" },
      }),
      context("entra"),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({
      identity: "entra",
      authenticated: true,
      attributePresent: true,
    });
  });

  test("rejects an unknown identity route", async () => {
    const response = await GET(
      new Request("http://localhost/api/auth-status/other"),
      context("other"),
    );

    expect(response.status).toBe(400);
  });
});
